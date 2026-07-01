require "rails_helper"

RSpec.describe "Strict mode" do
  let(:acme) { Account.create!(name: "Acme") }

  before do
    TenantKit.without_tenant do
      Project.create!(account: acme, name: "Acme Site")
    end
  end

  context "when require_tenant is true (default) and no tenant is set" do
    it "raises NoTenantSet on a count query" do
      expect { Project.count }.to raise_error(TenantKit::NoTenantSet, /Project/)
    end

    it "raises NoTenantSet when loading records" do
      expect { Project.all.to_a }.to raise_error(TenantKit::NoTenantSet)
    end

    it "raises NoTenantSet on find_by" do
      expect { Project.find_by(name: "Acme Site") }.to raise_error(TenantKit::NoTenantSet)
    end

    it "does not raise inside without_tenant and returns all rows" do
      TenantKit.without_tenant do
        expect(Project.count).to eq(1)
      end
    end
  end

  context "when require_tenant is false and no tenant is set" do
    around do |example|
      TenantKit.config.require_tenant = false
      example.run
    ensure
      TenantKit.config.require_tenant = true
    end

    it "returns all rows without raising" do
      expect(Project.count).to eq(1)
      expect(Project.all.to_a.size).to eq(1)
    end
  end
end
