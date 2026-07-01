module TenantKit
  # Opt-in test helpers. Require and include where you need them — they are not
  # loaded by default.
  #
  # @example RSpec
  #   require "tenant_kit/testing"
  #   RSpec.configure do |config|
  #     config.include TenantKit::Testing
  #     config.after { TenantKit::Current.reset }
  #   end
  #
  #   it "does tenant work" do
  #     as_tenant(account) { expect(Project.count).to eq(0) }
  #   end
  module Testing
    # Runs the block scoped to +tenant+ (alias for {TenantKit.with_tenant}).
    #
    # @param tenant [Object]
    # @yield the block to run under +tenant+.
    # @return [Object] the block's return value.
    def as_tenant(tenant, &block)
      TenantKit.with_tenant(tenant, &block)
    end

    # Runs the block with tenant scoping disabled (alias for
    # {TenantKit.without_tenant}).
    #
    # @yield the block to run unscoped.
    # @return [Object] the block's return value.
    def without_tenant(&block)
      TenantKit.without_tenant(&block)
    end
  end
end
