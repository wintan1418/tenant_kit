require "rails_helper"

RSpec.describe "Tenant scoping" do
  let(:acme)   { Account.create!(name: "Acme") }
  let(:globex) { Account.create!(name: "Globex") }

  before do
    TenantKit.without_tenant do
      @acme_project   = Project.create!(account: acme, name: "Acme Site")
      @globex_project = Project.create!(account: globex, name: "Globex Site")
    end
  end

  it "returns only the current tenant's rows" do
    TenantKit.with_tenant(acme) do
      expect(Project.all).to contain_exactly(@acme_project)
    end
  end

  it "switches results when the tenant switches" do
    TenantKit.with_tenant(acme)   { expect(Project.pluck(:name)).to eq([ "Acme Site" ]) }
    TenantKit.with_tenant(globex) { expect(Project.pluck(:name)).to eq([ "Globex Site" ]) }
  end

  it "counts only the current tenant's rows" do
    TenantKit.with_tenant(acme) do
      expect(Project.count).to eq(1)
    end
  end

  it "restores the previous scope after with_tenant" do
    TenantKit.with_tenant(acme) do
      TenantKit.with_tenant(globex) do
        expect(Project.pluck(:name)).to eq([ "Globex Site" ])
      end
      expect(Project.pluck(:name)).to eq([ "Acme Site" ])
    end
  end

  it "sees all tenants' rows inside without_tenant" do
    TenantKit.without_tenant do
      expect(Project.count).to eq(2)
    end
  end

  it "does not leak the tenant scope into the account association" do
    TenantKit.with_tenant(acme) do
      expect(acme.projects).to contain_exactly(@acme_project)
    end
  end
end
