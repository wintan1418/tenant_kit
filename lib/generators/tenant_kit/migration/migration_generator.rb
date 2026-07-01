require "rails/generators"
require "rails/generators/active_record"

module TenantKit
  module Generators
    # Generates a migration adding the tenant reference to an owned table, with a
    # tenant-leading index and a NOT NULL foreign key.
    #
    #   rails g tenant_kit:migration Project
    class MigrationGenerator < Rails::Generators::NamedBase
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      # Writes db/migrate/add_<tenant>_to_<table>.rb.
      def create_migration_file
        migration_template "add_tenant_reference.rb.tt",
          "db/migrate/add_#{tenant_reference}_to_#{table_name}.rb"
      end

      private

      # @return [String] pluralized, snake_case table name for the owned model.
      def table_name
        name.tableize
      end

      # @return [String] the tenant association name derived from the configured
      #   tenant column (e.g. "account_id" => "account").
      def tenant_reference
        TenantKit.config.tenant_column.to_s.sub(/_id\z/, "")
      end

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
