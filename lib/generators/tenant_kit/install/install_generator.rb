require "rails/generators"
require "rails/generators/active_record"

module TenantKit
  module Generators
    # Installs TenantKit into a host app: writes the initializer and, unless the
    # tenant model already exists, scaffolds it plus a migration.
    #
    #   rails g tenant_kit:install
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :skip_tenant_model, type: :boolean, default: false,
        desc: "Do not create the tenant model or its migration"

      # Writes config/initializers/tenant_kit.rb.
      def create_initializer
        template "initializer.rb.tt", "config/initializers/tenant_kit.rb"
      end

      # Creates the tenant model and its migration, unless it already exists or
      # --skip-tenant-model was passed.
      def create_tenant_model
        return if options[:skip_tenant_model]
        return if tenant_model_exists?

        template "tenant_model.rb.tt", "app/models/#{tenant_singular}.rb"
        migration_template "tenant_migration.rb.tt",
          "db/migrate/create_#{tenant_plural}.rb"
      end

      # Prints post-install guidance.
      def show_readme
        say ""
        say "TenantKit installed.", :green
        say "  1. Review config/initializers/tenant_kit.rb"
        say "  2. Add `belongs_to_tenant` to each tenant-owned model"
        say "  3. Add the tenant column to owned tables: rails g tenant_kit:migration Project"
        say "  4. Resolve the tenant in ApplicationController, e.g."
        say "       set_current_tenant_by_subdomain(:#{tenant_singular}, :subdomain)"
        say ""
      end

      private

      def tenant_class_name
        TenantKit.config.tenant_class
      end

      def tenant_singular
        tenant_class_name.underscore
      end

      def tenant_plural
        tenant_singular.pluralize
      end

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end

      def tenant_model_exists?
        File.exist?(File.expand_path("app/models/#{tenant_singular}.rb", destination_root))
      end
    end
  end
end
