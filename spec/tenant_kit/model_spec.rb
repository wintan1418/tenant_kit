require "rails_helper"

RSpec.describe "belongs_to_tenant" do
  let(:acme) { Account.create!(name: "Acme") }

  it "declares the tenant association" do
    expect(Project.reflect_on_association(:account)).to be_present
    expect(Project.new).to respond_to(:account)
  end

  it "records the association and foreign key" do
    expect(Project._tenant_kit_association).to eq(:account)
    expect(Project._tenant_kit_foreign_key).to eq("account_id")
  end

  it "auto-assigns the current tenant to new records" do
    TenantKit.with_tenant(acme) do
      project = Project.create!(name: "Auto")
      expect(project.account).to eq(acme)
      expect(project.account_id).to eq(acme.id)
    end
  end

  it "does not overwrite an explicitly set tenant" do
    other = Account.create!(name: "Other")
    TenantKit.with_tenant(acme) do
      project = Project.create!(name: "Explicit", account: other)
      expect(project.account).to eq(other)
    end
  end

  it "validates presence of the tenant when none is set" do
    project = Project.new(name: "Orphan")
    expect(project).not_to be_valid
    expect(project.errors[:account]).to be_present
  end

  it "allows creating without a tenant inside without_tenant" do
    TenantKit.without_tenant do
      project = Project.new(name: "Seed", account: acme)
      expect(project).to be_valid
    end
  end

  it "supports an explicit association declaration" do
    expect(Invoice._tenant_kit_association).to eq(:account)
    TenantKit.with_tenant(acme) do
      invoice = Invoice.create!(number: "INV-1", amount_cents: 100)
      expect(invoice.account).to eq(acme)
    end
  end
end
