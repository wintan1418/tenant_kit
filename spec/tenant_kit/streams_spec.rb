require "rails_helper"

RSpec.describe TenantKit::Streams do
  let!(:acme)   { Account.create!(name: "Acme") }
  let!(:globex) { Account.create!(name: "Globex") }
  let(:project) { TenantKit.without_tenant { Project.create!(account: acme, name: "P") } }

  it "prefixes streamables with the current tenant" do
    TenantKit.with_tenant(acme) do
      expect(described_class.streamables(project, :tasks)).to eq([ acme, project, :tasks ])
      expect(described_class.stream_name(project, :tasks))
        .to eq("#{acme.to_gid_param}:#{project.to_gid_param}:tasks")
    end
  end

  it "builds the same names as turbo-rails" do
    TenantKit.with_tenant(acme) do
      turbo = Class.new { include Turbo::Streams::StreamName }.new
      expect(described_class.stream_name(project, "x")).to eq(turbo.send(:stream_name_from, [ acme, project, "x" ]))
    end
  end

  it "accepts an explicit tenant" do
    expect(described_class.stream_name("feed", tenant: globex)).to eq("#{globex.to_gid_param}:feed")
  end

  it "raises NoTenantSet with no tenant" do
    expect { described_class.stream_name("feed") }.to raise_error(TenantKit::NoTenantSet)
  end

  it "recognises a tenant's own stream names only" do
    name = described_class.stream_name("feed", tenant: acme)
    expect(described_class.tenant_stream?(name, tenant: acme)).to be(true)
    expect(described_class.tenant_stream?(acme.to_gid_param, tenant: acme)).to be(true)
    expect(described_class.tenant_stream?(name, tenant: globex)).to be(false)
    expect(described_class.tenant_stream?("#{acme.to_gid_param}0:feed", tenant: acme)).to be(false)
    expect(described_class.tenant_stream?(name, tenant: nil)).to be(false)
  end
end

RSpec.describe TenantKit::Turbo do
  include ActiveJob::TestHelper

  let!(:acme)   { Account.create!(name: "Acme") }
  let!(:globex) { Account.create!(name: "Globex") }

  describe "broadcasts_to_tenant" do
    it "broadcasts on a stream prefixed with the record's own tenant" do
      contract = TenantKit.with_tenant(acme) { Contract.create!(title: "c") }
      job = enqueued_jobs.find { |j| j["job_class"] == "Turbo::Streams::ActionBroadcastJob" }
      expect(job).to be_present
      expect(job["arguments"].first).to eq("#{acme.to_gid_param}:contracts")
      expect(contract.tenant_stream("x")).to eq([ acme, "x" ])
    end

    it "the later broadcast renders under the record's tenant" do
      TenantKit.without_tenant { Contract.create!(account: globex, title: "theirs") }
      clear_enqueued_jobs
      TenantKit.with_tenant(acme) { Contract.create!(title: "mine") }
      stream = "#{acme.to_gid_param}:contracts"
      expect { perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) }
        .to have_broadcasted_to(stream).with(a_string_including("mine (1 visible)"))
    end

    it "accepts a symbol, proc or string for the rest of the stream" do
      record = TenantKit.without_tenant { Project.create!(account: acme, name: "P") }
      expect(described_class.resolve_stream(record, :name)).to eq([ "P" ])
      expect(described_class.resolve_stream(record, ->(r) { [ r, :x ] })).to eq([ record, :x ])
      expect(described_class.resolve_stream(record, "fixed")).to eq([ "fixed" ])
      expect(described_class.resolve_stream(record, nil)).to eq([ "projects" ])
    end

    it "requires belongs_to_tenant first" do
      expect { Class.new(ApplicationRecord) { self.table_name = "users"; broadcasts_to_tenant } }
        .to raise_error(ArgumentError, /belongs_to_tenant/)
    end

    it "requires turbo-rails" do
      klass = Class.new { extend TenantKit::Turbo::Broadcasts }
      expect { klass.broadcasts_to_tenant }.to raise_error(TenantKit::Error, /turbo-rails/)
    end

    it "enqueues under the record's tenant even when saved inside without_tenant" do
      contract = TenantKit.without_tenant { Contract.create!(account: globex, title: "seeded") }
      job = enqueued_jobs.find { |j| j["job_class"] == "Turbo::Streams::ActionBroadcastJob" }
      expect(job["tenant_kit_gid"]).to eq(globex.to_global_id.to_s)
      expect { perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) }
        .to have_broadcasted_to("#{globex.to_gid_param}:contracts").with(a_string_including("seeded (1 visible)"))

      clear_enqueued_jobs
      TenantKit.without_tenant { contract.update!(title: "renamed") }
      expect(enqueued_jobs.last["arguments"].first).to eq("#{globex.to_gid_param}:contracts")

      expect { TenantKit.without_tenant { contract.destroy! } }
        .to have_broadcasted_to("#{globex.to_gid_param}:contracts").with(a_string_including("remove"))
    end
  end

  describe "view helpers" do
    let(:view) { ActionController::Base.helpers }

    it "turbo_stream_from_tenant signs the current tenant's stream name" do
      html = TenantKit.with_tenant(acme) { view.turbo_stream_from_tenant("projects") }
      signed = html[/signed-stream-name="([^"]+)"/, 1]
      expect(Turbo::StreamsChannel.verified_stream_name(CGI.unescapeHTML(signed))).to eq("#{acme.to_gid_param}:projects")
    end

    it "tenant_stream_name returns the current tenant's stream name" do
      TenantKit.with_tenant(acme) { expect(view.tenant_stream_name("p")).to eq("#{acme.to_gid_param}:p") }
    end

    it "raises with no tenant" do
      expect { view.turbo_stream_from_tenant("projects") }.to raise_error(TenantKit::NoTenantSet)
    end
  end
end
