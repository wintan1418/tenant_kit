require "rails_helper"
require "tenant_kit/testing"

RSpec.describe TenantKit::Testing do
  subject(:helper) { Object.new.extend(described_class) }

  let(:acme) { TenantKit.without_tenant { Account.create!(name: "Acme") } }

  it "as_tenant scopes the block to the tenant" do
    helper.as_tenant(acme) do
      expect(TenantKit::Current.tenant).to eq(acme)
    end
    expect(TenantKit::Current.tenant).to be_nil
  end

  it "without_tenant disables scoping in the block" do
    helper.as_tenant(acme) do
      helper.without_tenant do
        expect(TenantKit.scoping_disabled?).to be(true)
      end
    end
  end
end
