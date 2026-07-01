require "active_support"

require "tenant_kit/version"
require "tenant_kit/errors"
require "tenant_kit/configuration"
require "tenant_kit/current"
require "tenant_kit/railtie" if defined?(Rails::Railtie)

# TenantKit — row-level (shared-schema) multi-tenancy for Rails.
#
# The module itself exposes configuration and the sanctioned ways to move in and
# out of tenant scope: {with_tenant} and {without_tenant}. Everything else hangs
# off {TenantKit::Current} (the request-scoped current tenant) and the
# {TenantKit::Model} macro +belongs_to_tenant+.
module TenantKit
  class << self
    # @return [TenantKit::Configuration] the singleton configuration object.
    def config
      @config ||= Configuration.new
    end

    # Yields the configuration for editing, typically from an initializer.
    #
    # @yieldparam config [TenantKit::Configuration]
    # @return [TenantKit::Configuration]
    def configure
      yield config
      config
    end

    # Runs the block with +tenant+ as the current tenant, restoring the previous
    # tenant afterwards (even on error). The sanctioned way to switch tenants.
    #
    # @param tenant [Object] the tenant record to scope to.
    # @yield the block to run under +tenant+.
    # @return [Object] the block's return value.
    def with_tenant(tenant)
      previous = Current.tenant
      Current.tenant = tenant
      yield
    ensure
      Current.tenant = previous
    end

    # Runs the block with tenant scoping disabled — the single, greppable escape
    # hatch for admin tools, seeds, migrations, and the console. Restores the
    # previous state afterwards (even on error).
    #
    # @yield the block to run unscoped.
    # @return [Object] the block's return value.
    def without_tenant
      was = Current.scoping_disabled
      Current.scoping_disabled = true
      yield
    ensure
      Current.scoping_disabled = was
    end

    # @return [Boolean] true when a tenant is set and scoping is not disabled —
    #   i.e. queries should be filtered to the current tenant.
    def scoping_active?
      Current.tenant.present? && !Current.scoping_disabled
    end

    # @return [Boolean] true when inside a {without_tenant} block.
    def scoping_disabled?
      !!Current.scoping_disabled
    end
  end
end
