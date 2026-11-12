# Ensure GlobalID is fully wired (GlobalID.app set, GlobalID::Identification
# included into ActiveRecord::Base) — job propagation depends on it, and a host
# app that doesn't otherwise use GlobalID (e.g. a --minimal app) won't have its
# railtie loaded. Registering it here, at gem-load time, lets Rails run its
# initializers during boot exactly as a full app would.
require "global_id/railtie"

module TenantKit
  # Wires TenantKit into a Rails application on boot.
  class Railtie < ::Rails::Railtie
    initializer "tenant_kit.active_record" do
      ActiveSupport.on_load(:active_record) do
        include TenantKit::Model
        ActiveRecord::InsertAll.prepend(TenantKit::Model::InsertAllGuard)
        extend TenantKit::Turbo::Broadcasts
        include TenantKit::Turbo::Record
      end
    end

    initializer "tenant_kit.action_controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include TenantKit::ControllerConcern
      end
      ActiveSupport.on_load(:action_controller_api) do
        include TenantKit::ControllerConcern
      end
    end

    initializer "tenant_kit.action_view" do
      ActiveSupport.on_load(:action_view) do
        include TenantKit::Turbo::Helper
      end
    end

    initializer "tenant_kit.active_job" do
      ActiveSupport.on_load(:active_job) do
        include TenantKit::Job if TenantKit.config.propagate_to_jobs
      end
    end

    # Runs after the app's initializers, so config.postgres_rls set in
    # config/initializers/tenant_kit.rb is honoured.
    config.after_initialize do
      TenantKit::PostgresRLS.install! if TenantKit.config.postgres_rls
    end
  end
end
