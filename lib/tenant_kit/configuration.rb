module TenantKit
  # Holds the gem's configuration. Access the singleton via {TenantKit.config}
  # and set values in +config/initializers/tenant_kit.rb+ through
  # {TenantKit.configure}.
  #
  # @example
  #   TenantKit.configure do |config|
  #     config.tenant_class  = "Account"
  #     config.tenant_column = "account_id"
  #   end
  class Configuration
    POSTGRES_RLS_STRATEGIES = %i[session transaction].freeze
    EXPLICIT_SCOPING_GUARDS = [ :raise, :log, false ].freeze

    # @return [String] name of the model that represents a tenant (e.g. "Account").
    attr_accessor :tenant_class

    # @return [String] foreign-key column on tenant-owned tables (e.g. "account_id").
    attr_accessor :tenant_column

    # @return [Boolean] strict mode: raise {NoTenantSet} when a tenant-scoped
    #   query runs with no current tenant (and not inside +without_tenant+).
    attr_accessor :require_tenant

    # @return [Boolean] carry the current tenant into ActiveJob background jobs.
    attr_accessor :propagate_to_jobs

    # @return [Boolean] raise if a job is performed with no captured tenant
    #   (only consulted when {#propagate_to_jobs} is true).
    attr_accessor :raise_on_missing_job_tenant

    # @return [Boolean] refuse writes that cross a tenant boundary (default
    #   +true+): changing a persisted record's tenant, saving a record under a
    #   tenant other than the current one, and +insert_all+ / +upsert_all+ rows
    #   that name another tenant. All are allowed inside +without_tenant+.
    attr_accessor :prevent_cross_tenant_writes

    # @return [Boolean] add the tenant condition to the UPDATE / DELETE that
    #   record-level writes run (+save+, +update_columns+, +destroy+, +reload+)
    #   via Rails' +default_scope all_queries: true+ (default +false+). Read when
    #   +belongs_to_tenant+ runs, so set it in an initializer.
    attr_accessor :scope_record_writes

    # @return [Boolean] when a job runs under its enqueued tenant, raise
    #   {TenantMismatch} if a deserialized argument is a tenant-owned record of
    #   another tenant (default +true+).
    attr_accessor :verify_job_arguments

    # @return [Boolean] enable the PostgreSQL Row-Level Security integration
    #   (default +false+). See {TenantKit::PostgresRLS}.
    attr_accessor :postgres_rls

    # @return [Symbol] +:session+ (default) or +:transaction+. See
    #   {TenantKit::PostgresRLS}.
    attr_reader :postgres_rls_strategy

    # @return [Boolean] whether +without_tenant+ sets the RLS bypass setting
    #   (default +true+). Set to +false+ when unscoped work must go through a
    #   separate, privileged (+BYPASSRLS+) database role instead.
    attr_accessor :postgres_rls_bypass

    # @return [String] name of the PostgreSQL setting that carries the tenant id
    #   (default +"tenant_kit.tenant_id"+).
    attr_accessor :postgres_rls_setting

    # @return [String] name of the PostgreSQL setting that signals
    #   +without_tenant+ (default +"tenant_kit.bypass"+).
    attr_accessor :postgres_rls_bypass_setting

    def initialize
      @tenant_class                = "Account"
      @tenant_column               = "account_id"
      @require_tenant              = true
      @propagate_to_jobs           = true
      @raise_on_missing_job_tenant = false
      @prevent_cross_tenant_writes = true
      @scope_record_writes         = false
      @verify_job_arguments        = true
      @explicit_scoping_guard      = nil
      @postgres_rls                = false
      @postgres_rls_strategy       = :session
      @postgres_rls_bypass         = true
      @postgres_rls_setting        = "tenant_kit.tenant_id"
      @postgres_rls_bypass_setting = "tenant_kit.bypass"
    end

    # @param strategy [Symbol, String] +:session+ or +:transaction+.
    def postgres_rls_strategy=(strategy)
      strategy = strategy.to_sym
      unless POSTGRES_RLS_STRATEGIES.include?(strategy)
        raise ArgumentError, "postgres_rls_strategy must be one of #{POSTGRES_RLS_STRATEGIES.inspect}"
      end

      @postgres_rls_strategy = strategy
    end

    # What happens when an explicit-mode model is queried without
    # +for_current_tenant+: +:raise+, +:log+, or +false+ (off). Defaults to
    # +:raise+ in development and test and +:log+ everywhere else.
    #
    # @return [Symbol, false]
    def explicit_scoping_guard
      return @explicit_scoping_guard unless @explicit_scoping_guard.nil?

      local = defined?(Rails) && Rails.respond_to?(:env) && Rails.env.local?
      local ? :raise : :log
    end

    # @param mode [Symbol, false, nil] +:raise+, +:log+, +false+, or +nil+ for
    #   the environment-dependent default.
    def explicit_scoping_guard=(mode)
      unless mode.nil? || EXPLICIT_SCOPING_GUARDS.include?(mode)
        raise ArgumentError, "explicit_scoping_guard must be one of #{EXPLICIT_SCOPING_GUARDS.inspect} (or nil)"
      end

      @explicit_scoping_guard = mode
    end

    # Resolves {#tenant_class} to the actual constant, lazily so it works with
    # Rails autoloading / reloading.
    #
    # @return [Class] the tenant model class.
    def tenant_model
      tenant_class.to_s.constantize
    end
  end
end
