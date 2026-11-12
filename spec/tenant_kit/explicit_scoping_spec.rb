require "rails_helper"

RSpec.describe "belongs_to_tenant scoping: :explicit" do
  let!(:acme)   { Account.create!(name: "Acme") }
  let!(:globex) { Account.create!(name: "Globex") }
  let!(:mine)   { TenantKit.without_tenant { Note.create!(account: acme, body: "mine") } }
  let!(:theirs) { TenantKit.without_tenant { Note.create!(account: globex, body: "theirs") } }

  def as_acme(&block) = TenantKit.with_tenant(acme, &block)

  it "records the scoping mode" do
    expect(Note._tenant_kit_scoping).to eq(:explicit)
    expect(Project._tenant_kit_scoping).to eq(:default)
  end

  it "rejects an unknown scoping mode" do
    expect { Class.new(ApplicationRecord) { self.table_name = "notes"; belongs_to_tenant scoping: :loose } }
      .to raise_error(ArgumentError, /scoping/)
  end

  describe "for_current_tenant" do
    it "returns only the current tenant's rows" do
      as_acme do
        expect(Note.for_current_tenant.to_a).to eq([ mine ])
        expect(Note.for_current_tenant.find_by(id: theirs.id)).to be_nil
        expect(Note.where(body: "theirs").for_current_tenant.count).to eq(0)
      end
    end

    it "raises NoTenantSet with no tenant in strict mode" do
      expect { Note.for_current_tenant }.to raise_error(TenantKit::NoTenantSet)
    end

    it "returns no rows with no tenant when strict mode is off" do
      TenantKit.config.require_tenant = false
      expect(Note.for_current_tenant.to_a).to be_empty
    ensure
      TenantKit.config.require_tenant = true
    end

    it "returns every row inside without_tenant" do
      TenantKit.without_tenant { expect(Note.for_current_tenant.count).to eq(2) }
    end

    it "keeps the tenant condition when merged with an association" do
      as_acme { expect(globex.notes.for_current_tenant.to_a).to be_empty }
    end
  end

  describe "the guard (raises in development and test by default)" do
    it "defaults to :raise in the test environment" do
      expect(TenantKit.config.explicit_scoping_guard).to eq(:raise)
    end

    it "raises ExplicitScopeMissing for unscoped reads and writes" do
      as_acme do
        [
          -> { Note.all.to_a },
          -> { Note.find(theirs.id) },
          -> { Note.find_by(body: "theirs") },
          -> { Note.count },
          -> { Note.pluck(:body) },
          -> { Note.ids },
          -> { Note.exists?(theirs.id) },
          -> { Note.where(body: "x").update_all(body: "y") },
          -> { Note.where(body: "x").delete_all }
        ].each { |query| expect(&query).to raise_error(TenantKit::ExplicitScopeMissing, /Note/) }
      end
    end

    it "accepts an explicit condition on the tenant column" do
      as_acme { expect(Note.where(account_id: acme.id).to_a).to eq([ mine ]) }
    end

    it "accepts association reads from a loaded record" do
      as_acme { expect(acme.notes.to_a).to eq([ mine ]) }
    end

    it "is off inside without_tenant" do
      TenantKit.without_tenant { expect(Note.count).to eq(2) }
    end

    it "logs and instruments instead of raising in :log mode" do
      TenantKit.config.explicit_scoping_guard = :log
      events = []
      callback = ->(*, payload) { events << payload[:model] }
      ActiveSupport::Notifications.subscribed(callback, "explicit_scope_missing.tenant_kit") do
        expect(Rails.logger).to receive(:warn).with(/scoping: :explicit/)
        as_acme { expect(Note.count).to eq(2) }
      end
      expect(events).to eq([ "Note" ])
    ensure
      TenantKit.config.explicit_scoping_guard = nil
    end

    it "can be disabled" do
      TenantKit.config.explicit_scoping_guard = false
      as_acme { expect(Note.count).to eq(2) }
    ensure
      TenantKit.config.explicit_scoping_guard = nil
    end

    it "defaults to :log outside development and test" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      expect(TenantKit::Configuration.new.explicit_scoping_guard).to eq(:log)
    end

    it "rejects an unknown guard mode" do
      expect { TenantKit::Configuration.new.explicit_scoping_guard = :shout }.to raise_error(ArgumentError)
    end
  end

  describe "everything else still applies" do
    it "auto-assigns the tenant and refuses cross-tenant writes" do
      as_acme do
        expect(Note.create!(body: "new").account).to eq(acme)
        expect(Note.new(body: "planted", account: globex)).not_to be_valid
        expect { Note.insert_all([ { body: "bulk", account_id: globex.id } ]) }.to raise_error(TenantKit::CrossTenantWrite)
      end
    end

    it "fills the tenant on insert_all" do
      as_acme { Note.insert_all([ { body: "bulk" } ]) }
      expect(TenantKit.without_tenant { Note.find_by!(body: "bulk").account_id }).to eq(acme.id)
    end
  end
end
