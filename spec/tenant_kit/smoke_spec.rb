require "rails_helper"

RSpec.describe "TenantKit smoke test" do
  it "boots the dummy app and loads the gem" do
    expect(defined?(TenantKit)).to eq("constant")
    expect(TenantKit::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "has the tenant and owned tables in the test schema" do
    expect(ActiveRecord::Base.connection.tables).to include("accounts", "projects", "invoices")
  end

  it "can create an account" do
    account = Account.create!(name: "Acme")
    expect(account).to be_persisted
  end
end
