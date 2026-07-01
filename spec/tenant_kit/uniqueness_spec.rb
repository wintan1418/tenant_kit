require "rails_helper"

RSpec.describe "validates_uniqueness_to_tenant" do
  let(:acme)   { Account.create!(name: "Acme") }
  let(:globex) { Account.create!(name: "Globex") }

  it "allows the same value under different tenants" do
    TenantKit.with_tenant(acme)   { Project.create!(name: "A", slug: "dashboard") }
    TenantKit.with_tenant(globex) { expect(Project.new(name: "B", slug: "dashboard")).to be_valid }
  end

  it "blocks duplicate values within one tenant" do
    TenantKit.with_tenant(acme) do
      Project.create!(name: "A", slug: "dashboard")
      dup = Project.new(name: "B", slug: "dashboard")
      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
    end
  end

  it "scopes invoice numbers per tenant" do
    TenantKit.with_tenant(acme)   { Invoice.create!(number: "INV-1") }
    TenantKit.with_tenant(globex) { expect(Invoice.new(number: "INV-1")).to be_valid }
    TenantKit.with_tenant(acme)   { expect(Invoice.new(number: "INV-1")).not_to be_valid }
  end

  it "raises if called before belongs_to_tenant" do
    klass = Class.new(ApplicationRecord) do
      self.table_name = "projects"
    end
    expect { klass.validates_uniqueness_to_tenant(:slug) }.to raise_error(ArgumentError)
  end
end
