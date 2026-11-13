module TenantKit
  # Base class for all TenantKit errors.
  class Error < StandardError; end

  # Raised when a tenant-scoped model is queried with no current tenant set,
  # while strict mode (+config.require_tenant+) is enabled and execution is not
  # inside a {TenantKit.without_tenant} block. Signals a would-be cross-tenant
  # read rather than silently returning another tenant's data.
  class NoTenantSet < Error; end

  # Raised when a write would put a row under a tenant other than the current
  # one through an API that skips validations — +insert_all+ / +upsert_all+
  # rows naming another tenant.
  class CrossTenantWrite < Error; end

  # Raised when a background job is handed a tenant-owned record that belongs
  # to a different tenant than the one the job was enqueued under.
  class TenantMismatch < Error; end

  # Raised (in development and test, by default) when a model declared with
  # +belongs_to_tenant scoping: :explicit+ is queried without
  # +for_current_tenant+ or an explicit condition on the tenant column.
  class ExplicitScopeMissing < Error; end
end
