require "rails_helper"

RSpec.describe TenantKit::Cable do
  let!(:acme)   { Account.create!(name: "Acme", subdomain: "acme") }
  let!(:globex) { Account.create!(name: "Globex", subdomain: "globex") }
  let!(:project) { TenantKit.without_tenant { Project.create!(account: acme, name: "P") } }
  let!(:foreign) { TenantKit.without_tenant { Project.create!(account: globex, name: "F") } }

  describe TenantKit::Cable::Connection, type: :channel do
    it "runs each channel command under the connection's tenant" do
      connection = ApplicationCable::Connection.allocate
      connection.instance_variable_set(:@current_tenant, acme)
      seen = nil
      connection.run_callbacks(:command) { seen = [ TenantKit::Current.tenant, Project.count ] }
      expect(seen).to eq([ acme, 1 ])
      expect(TenantKit::Current.tenant).to be_nil
    end

    it "runs commands without a tenant when the connection has none" do
      connection = ApplicationCable::Connection.allocate
      seen = :unset
      connection.run_callbacks(:command) { seen = TenantKit::Current.tenant }
      expect(seen).to be_nil
    end
  end

  # Action Cable runs each command inside the app executor (the cable worker),
  # with TenantKit::Cable::Connection setting the tenant inside it. Specs
  # reproduce that so Rails' own executor wrap around +subscribe+ is nested,
  # as in production.
  def as_cable_command(tenant, &block)
    Rails.application.executor.wrap { TenantKit.with_tenant(tenant, &block) }
  end

  describe ProjectChannel, type: :channel do
    before { stub_connection current_tenant: acme }

    it "streams the tenant-prefixed broadcasting for an owned record" do
      as_cable_command(acme) { subscribe(id: project.id) }
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for([ acme, project ])
      expect(subscription.streams).to eq([ ProjectChannel.tenant_broadcasting_for(acme, project) ])
    end

    it "rejects a record of another tenant" do
      as_cable_command(acme) { subscribe(id: foreign.id) }
      expect(subscription).to be_rejected
    end

    it "rejects when the connection has no tenant" do
      stub_connection current_tenant: nil
      subscribe(id: project.id)
      expect(subscription).to be_rejected
    end

    it "broadcast_to_tenant targets the tenant-prefixed broadcasting" do
      expect { ProjectChannel.broadcast_to_tenant(acme, project, { html: "x" }) }
        .to have_broadcasted_to(ProjectChannel.tenant_broadcasting_for(acme, project)).with(html: "x")
    end
  end

  describe "reject_unless_current_tenant_owns" do
    let(:channel_class) do
      Class.new(ApplicationCable::Channel) do
        def self.name = "OwnsChannel"
        public :reject_unless_current_tenant_owns
      end
    end

    it "rejects foreign records and accepts owned and global ones" do
      channel = channel_class.new(ActionCable::Channel::ConnectionStub.new(current_tenant: acme), "id")
      expect(channel.reject_unless_current_tenant_owns(project)).to be(false)
      expect(channel.reject_unless_current_tenant_owns(User.new)).to be(false)
      expect(channel.reject_unless_current_tenant_owns(foreign)).to be(true)
    end

    it "falls back to the current tenant when the connection identifies none" do
      channel = channel_class.new(ActionCable::Channel::ConnectionStub.new, "id")
      expect(channel.reject_unless_current_tenant_owns(project)).to be(true)
      TenantKit.with_tenant(acme) { expect(channel.reject_unless_current_tenant_owns(project)).to be(false) }
    end
  end

  describe TenantStreamsChannel, type: :channel do
    before { stub_connection current_tenant: acme }

    def signed(name) = Turbo::StreamsChannel.signed_stream_name(name)

    it "accepts the current tenant's signed stream" do
      as_cable_command(acme) { subscribe(signed_stream_name: signed([ acme, "projects" ])) }
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("#{acme.to_gid_param}:projects")
    end

    it "rejects another tenant's signed stream" do
      as_cable_command(acme) { subscribe(signed_stream_name: signed([ globex, "projects" ])) }
      expect(subscription).to be_rejected
    end

    it "rejects a stream that is not tenant-prefixed" do
      as_cable_command(acme) { subscribe(signed_stream_name: signed("projects")) }
      expect(subscription).to be_rejected
    end
  end
end
