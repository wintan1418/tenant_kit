# Ensure GlobalID is fully wired (GlobalID.app set, GlobalID::Identification
# included into ActiveRecord::Base) — job propagation depends on it, and a host
# app that doesn't otherwise use GlobalID (e.g. a --minimal app) won't have its
# railtie loaded. Registering it here, at gem-load time, lets Rails run its
# initializers during boot exactly as a full app would.
require "global_id/railtie"

module TenantKit
  # Wires TenantKit into a Rails application on boot. Each concern is included
  # only if it has been required, so the gem boots correctly at every build
  # milestone. Hooks are guarded with +defined?+ so a partially-built gem never
  # crashes the host app.
  class Railtie < ::Rails::Railtie
    initializer "tenant_kit.active_record" do
      ActiveSupport.on_load(:active_record) do
        include TenantKit::Model if defined?(TenantKit::Model)
      end
    end

    initializer "tenant_kit.action_controller" do
      ActiveSupport.on_load(:action_controller_base) do
        include TenantKit::ControllerConcern if defined?(TenantKit::ControllerConcern)
      end
      ActiveSupport.on_load(:action_controller_api) do
        include TenantKit::ControllerConcern if defined?(TenantKit::ControllerConcern)
      end
    end

    initializer "tenant_kit.active_job" do
      ActiveSupport.on_load(:active_job) do
        include TenantKit::Job if defined?(TenantKit::Job) && TenantKit.config.propagate_to_jobs
      end
    end
  end
end
