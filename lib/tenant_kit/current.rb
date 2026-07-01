require "active_support/current_attributes"

module TenantKit
  # Request-scoped holder for the current tenant, built on
  # +ActiveSupport::CurrentAttributes+ so state is automatically reset between
  # requests (and between jobs) — never {Thread.current} directly, which would
  # bleed across requests on a reused thread.
  class Current < ActiveSupport::CurrentAttributes
    # @return [Object, nil] the current tenant record.
    attribute :tenant

    # Internal flag toggled by {TenantKit.without_tenant} to disable scoping.
    # @return [Boolean, nil]
    attribute :scoping_disabled
  end
end
