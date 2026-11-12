require "rails/generators"
require "rails/generators/active_record"

module TenantKit
  module Generators
    # Generates a migration that enables PostgreSQL Row-Level Security with
    # TenantKit's isolation policy on tenant-owned tables.
    #
    #   rails g tenant_kit:rls                 # every model that calls belongs_to_tenant
    #   rails g tenant_kit:rls Project Invoice # just these
    #   rails g tenant_kit:rls --column-type=uuid --no-bypass
    #
    # The migration is plain SQL (it does not call TenantKit at migrate time).
    # See docs/POSTGRES_RLS.md before running it: the app must connect as a
    # role without SUPERUSER / BYPASSRLS, and config.postgres_rls must be on.
    class RlsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      argument :models, type: :array, default: [], banner: "Model Model ..."

      class_option :column_type, type: :string, default: nil,
        desc: "SQL type of the tenant column (default: read from the database, else bigint)"
      class_option :bypass, type: :boolean, default: true,
        desc: "Let TenantKit.without_tenant bypass the policy via the tenant_kit.bypass setting"

      # Writes db/migrate/enable_tenant_kit_rls*.rb.
      def create_migration_file
        if tables.empty?
          say "No tenant-owned models found. Pass model names: rails g tenant_kit:rls Project", :red
          return
        end

        migration_template "enable_rls.rb.tt", "db/migrate/#{rls_migration_name}.rb"
      end

      # Prints the steps the migration alone does not cover.
      def show_readme
        return if tables.empty?

        say ""
        say "Next steps (see docs/POSTGRES_RLS.md):", :green
        say "  1. Set config.postgres_rls = true in config/initializers/tenant_kit.rb"
        say "  2. Connect the app as a role WITHOUT superuser or BYPASSRLS"
        say "  3. Using PgBouncer in transaction mode? Set config.postgres_rls_strategy = :transaction"
        say ""
      end

      private

      # @return [Array<Hash>] one entry per table: +:table+, +:column+, +:type+.
      def tables
        @tables ||= resolve_models.filter_map do |model|
          next unless model

          {
            table: model.table_name,
            column: model._tenant_kit_foreign_key,
            type: options[:column_type] || column_type_for(model)
          }
        end.uniq { |entry| entry[:table] }
      end

      def resolve_models
        if models.empty?
          Rails.application.eager_load! if defined?(Rails.application) && Rails.application
          ActiveRecord::Base.descendants.select do |klass|
            !klass.abstract_class? && klass.respond_to?(:tenant_owned?) && klass.tenant_owned? && klass.base_class == klass
          end.sort_by(&:name)
        else
          models.map do |name|
            klass = name.camelize.safe_constantize
            unless klass.respond_to?(:tenant_owned?) && klass.tenant_owned?
              say "Skipping #{name}: not a model that calls belongs_to_tenant", :yellow
              next
            end
            klass
          end
        end
      end

      def column_type_for(model)
        model.columns_hash[model._tenant_kit_foreign_key]&.sql_type.presence&.downcase || "bigint"
      rescue StandardError
        "bigint"
      end

      def enable_sql(entry)
        TenantKit::PostgresRLS.enable_sql(entry[:table], column: entry[:column], type: entry[:type], bypass: options[:bypass])
      end

      def disable_sql(entry)
        TenantKit::PostgresRLS.disable_sql(entry[:table])
      end

      def rls_migration_name
        models.empty? ? "enable_tenant_kit_rls" : "enable_tenant_kit_rls_on_#{tables.map { |t| t[:table].tr(".", "_") }.join("_")}"
      end

      def rls_migration_class_name
        rls_migration_name.camelize
      end

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
