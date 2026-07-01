module TenantKit
  # Base class for all TenantKit errors.
  class Error < StandardError; end

  # Raised when a tenant-scoped model is queried with no current tenant set,
  # while strict mode (+config.require_tenant+) is enabled and execution is not
  # inside a {TenantKit.without_tenant} block. Signals a would-be cross-tenant
  # read rather than silently returning another tenant's data.
  class NoTenantSet < Error; end
end
