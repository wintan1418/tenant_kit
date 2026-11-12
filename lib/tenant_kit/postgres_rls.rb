module TenantKit
  # Optional PostgreSQL Row-Level Security integration — defence in depth under
  # TenantKit's Active Record scoping.
  #
  # With +config.postgres_rls = true+, TenantKit keeps two PostgreSQL settings
  # in step with {TenantKit::Current} on every connection it runs SQL on:
  #
  # * +tenant_kit.tenant_id+ — the current tenant's id while scoping is
  #   active, otherwise empty.
  # * +tenant_kit.bypass+ — +"on"+ inside {TenantKit.without_tenant} (when
  #   +config.postgres_rls_bypass+ is true), otherwise +"off"+.
  #
  # The +tenant_kit:rls+ generator writes a migration that enables (and forces)
  # RLS on each tenant table with a policy comparing the tenant column to
  # +current_setting('tenant_kit.tenant_id', true)+. The database then refuses
  # cross-tenant reads and writes even for SQL that never went through a
  # TenantKit scope — +find_by_sql+, +connection.select_all+, +unscoped+,
  # +update_columns+ on a foreign record.
  #
  # == How the setting is applied
  #
  # The setting is applied inside Active Record's +with_raw_connection+, right
  # before a statement runs on the connection — so it always reflects the
  # tenant of the code issuing the statement, whichever pooled connection that
  # code happens to hold. TenantKit remembers what it last set on each
  # connection and only re-issues +set_config+ when the tenant changes, after
  # a transaction ends, after a rollback / rollback-to-savepoint, or after a
  # reconnect or reset.
  #
  # Strategies (+config.postgres_rls_strategy+):
  #
  # +:session+ (default):: +set_config(..., false)+ — session-scoped. Safe with
  #   Active Record's connection pool (one thread uses a connection at a time and
  #   the value is re-checked before each statement) and with PgBouncer in
  #   *session* pooling mode. *Not safe* with PgBouncer *transaction* pooling:
  #   the server connection can change between the +set_config+ and the query.
  # +:transaction+:: +set_config(..., true)+ (+SET LOCAL+ semantics) issued
  #   inside each transaction. Safe with PgBouncer transaction pooling. Statements
  #   that run *outside* a transaction get no tenant at all, so the policy denies
  #   them (fail closed) — run tenant work inside +transaction do ... end+.
  #
  # == Caveats (see docs/POSTGRES_RLS.md)
  #
  # * Superusers and roles with +BYPASSRLS+ ignore policies. The app must connect
  #   as an ordinary role; the generated migration also uses +FORCE ROW LEVEL
  #   SECURITY+ so the table owner is subject to the policy.
  # * SQL sent through +connection.raw_connection+ bypasses the sync.
  # * Background threads (e.g. +load_async+ with an async executor) have no
  #   +Current+ tenant, so their queries see no tenant rows.
  module PostgresRLS
    POLICY_NAME = "tenant_kit_isolation".freeze
    IDENTIFIER = /\A[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?\z/

    # Adapter methods after which what TenantKit last applied may no longer be
    # in effect. Transaction boundaries end transaction-local values; rollbacks
    # also undo session-level values set inside the rolled-back work; resets
    # and reconnects start a new session.
    INVALIDATES_LOCAL = %i[begin_db_transaction begin_isolated_db_transaction commit_db_transaction].freeze
    INVALIDATES_ALL = %i[exec_rollback_db_transaction exec_rollback_to_savepoint reset! disconnect! reconnect!].freeze

    # What TenantKit applies when no tenant is current.
    CLEARED = [ "", "off" ].freeze

    # Prepended onto the PostgreSQL adapter by {PostgresRLS.install!}.
    module AdapterExtension
      private

      def with_raw_connection(allow_retry: false, materialize_transactions: true)
        super do |conn|
          TenantKit::PostgresRLS.sync(self, conn) if materialize_transactions
          yield conn
        end
      end
    end

    class << self
      # Prepends the sync onto +ActiveRecord::ConnectionAdapters::PostgreSQLAdapter+
      # (now, or when it loads). Idempotent. Called by the railtie when
      # +config.postgres_rls+ is true.
      #
      # @return [void]
      def install!
        ActiveSupport.on_load(:active_record_postgresqladapter) do
          TenantKit::PostgresRLS.prepend_into(self)
        end
      end

      # @api private
      def prepend_into(adapter_class)
        return if adapter_class < AdapterExtension

        invalidation = Module.new do
          { INVALIDATES_LOCAL => %i[@tenant_kit_rls_local],
            INVALIDATES_ALL => %i[@tenant_kit_rls_local @tenant_kit_rls_session] }.each do |names, ivars|
            names.each do |name|
              next unless adapter_class.method_defined?(name) || adapter_class.private_method_defined?(name)

              define_method(name) do |*args, **kwargs, &block|
                super(*args, **kwargs, &block)
              ensure
                ivars.each { |ivar| instance_variable_set(ivar, nil) }
              end
            end
          end
        end

        adapter_class.prepend(invalidation)
        adapter_class.prepend(AdapterExtension)
      end

      # Applies the current tenant to +conn+ if it differs from what TenantKit
      # last applied there.
      #
      # * +:session+ — the value is applied at session level.
      # * +:transaction+ — inside a transaction the value is applied
      #   transaction-locally; outside one, any session-level value is cleared
      #   so autocommit statements run with no tenant (fail closed).
      #
      # @api private
      def sync(adapter, conn)
        config = TenantKit.config
        return unless config.postgres_rls

        desired = [
          TenantKit.scoping_active? ? TenantKit.current_tenant_id.to_s : "",
          config.postgres_rls_bypass && TenantKit.scoping_disabled? ? "on" : "off"
        ]

        if config.postgres_rls_strategy == :transaction
          if adapter.transaction_open?
            apply(adapter, conn, :@tenant_kit_rls_local, desired, local: true)
          else
            apply(adapter, conn, :@tenant_kit_rls_session, CLEARED, local: false)
          end
        else
          apply(adapter, conn, :@tenant_kit_rls_session, desired, local: false)
        end
      end

      # SQL that enables RLS on +table+ with TenantKit's isolation policy.
      #
      # @param table [String] table name, optionally schema-qualified.
      # @param column [String] the tenant column.
      # @param type [String] SQL type of the tenant column (+bigint+, +uuid+, ...).
      # @param bypass [Boolean] include the +tenant_kit.bypass+ escape in the policy.
      # @return [Array<String>] statements, in order.
      def enable_sql(table, column: TenantKit.config.tenant_column, type: "bigint", bypass: true,
                     setting: TenantKit.config.postgres_rls_setting,
                     bypass_setting: TenantKit.config.postgres_rls_bypass_setting)
        t = quote_identifier(table)
        c = quote_identifier(column)
        raise ArgumentError, "unsupported column type #{type.inspect}" unless type.to_s.match?(/\A[a-z][a-z0-9_ ]*\z/)

        condition = "#{c} = NULLIF(current_setting(#{quote_literal(setting)}, true), '')::#{type}"
        condition = "(#{condition}) OR current_setting(#{quote_literal(bypass_setting)}, true) = 'on'" if bypass

        [
          "ALTER TABLE #{t} ENABLE ROW LEVEL SECURITY",
          "ALTER TABLE #{t} FORCE ROW LEVEL SECURITY",
          "CREATE POLICY #{POLICY_NAME} ON #{t} AS PERMISSIVE FOR ALL USING (#{condition}) WITH CHECK (#{condition})"
        ]
      end

      # SQL that removes TenantKit's policy and disables RLS on +table+.
      #
      # @return [Array<String>]
      def disable_sql(table)
        t = quote_identifier(table)
        [
          "DROP POLICY IF EXISTS #{POLICY_NAME} ON #{t}",
          "ALTER TABLE #{t} NO FORCE ROW LEVEL SECURITY",
          "ALTER TABLE #{t} DISABLE ROW LEVEL SECURITY"
        ]
      end

      private

      def apply(adapter, conn, ivar, values, local:)
        state = adapter.instance_variable_get(ivar)
        return if state && state[0].equal?(conn) && state[1] == values

        config = TenantKit.config
        conn.exec_params(
          "SELECT set_config($1, $2, $5), set_config($3, $4, $5)",
          [ config.postgres_rls_setting, values[0], config.postgres_rls_bypass_setting, values[1], local.to_s ]
        )
        adapter.instance_variable_set(ivar, [ conn, values ])
      end

      def quote_identifier(name)
        name = name.to_s
        raise ArgumentError, "invalid SQL identifier #{name.inspect}" unless name.match?(IDENTIFIER)

        name.split(".").map { |part| %("#{part}") }.join(".")
      end

      def quote_literal(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end
    end
  end
end
