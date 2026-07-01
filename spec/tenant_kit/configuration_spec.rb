require "rails_helper"

RSpec.describe TenantKit::Configuration do
  it "has correct defaults" do
    config = described_class.new

    expect(config.tenant_class).to eq("Account")
    expect(config.tenant_column).to eq("account_id")
    expect(config.require_tenant).to be(true)
    expect(config.propagate_to_jobs).to be(true)
    expect(config.raise_on_missing_job_tenant).to be(false)
  end

  it "resolves tenant_class to the constant" do
    config = described_class.new
    expect(config.tenant_model).to eq(Account)
  end
end

RSpec.describe TenantKit do
  describe ".configure" do
    around do |example|
      original = described_class.config.dup
      example.run
      described_class.instance_variable_set(:@config, original)
    end

    it "yields the config and applies overrides" do
      described_class.configure do |config|
        config.tenant_class = "Organization"
        config.require_tenant = false
      end

      expect(described_class.config.tenant_class).to eq("Organization")
      expect(described_class.config.require_tenant).to be(false)
    end
  end

  describe "scoping control" do
    let(:account) { Account.create!(name: "Acme") }

    it "with_tenant sets and restores the current tenant" do
      expect(described_class::Current.tenant).to be_nil

      described_class.with_tenant(account) do
        expect(described_class::Current.tenant).to eq(account)
        expect(described_class.scoping_active?).to be(true)
      end

      expect(described_class::Current.tenant).to be_nil
      expect(described_class.scoping_active?).to be(false)
    end

    it "with_tenant restores even when the block raises" do
      expect do
        described_class.with_tenant(account) { raise "boom" }
      end.to raise_error("boom")

      expect(described_class::Current.tenant).to be_nil
    end

    it "without_tenant disables scoping and restores it" do
      described_class.with_tenant(account) do
        expect(described_class.scoping_active?).to be(true)

        described_class.without_tenant do
          expect(described_class.scoping_disabled?).to be(true)
          expect(described_class.scoping_active?).to be(false)
        end

        expect(described_class.scoping_disabled?).to be(false)
        expect(described_class.scoping_active?).to be(true)
      end
    end
  end
end
