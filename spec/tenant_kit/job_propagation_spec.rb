require "rails_helper"

RSpec.describe "Job tenant propagation", type: :job do
  include ActiveJob::TestHelper

  let(:acme) do
    TenantKit.without_tenant { Account.create!(name: "Acme") }
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    TenantProbeJob::RESULTS.clear
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  it "captures the tenant GlobalID into the serialized payload" do
    job = TenantKit.with_tenant(acme) do
      TenantProbeJob.new.tap { |j| j.run_callbacks(:enqueue) { } }
    end
    expect(job.serialize["tenant_kit_gid"]).to eq(acme.to_global_id.to_s)
  end

  it "round-trips the tenant through serialize/deserialize" do
    TenantKit.with_tenant(acme) do
      data = TenantProbeJob.new.tap { |j| j.run_callbacks(:enqueue) { } }.serialize
      restored = TenantProbeJob.new
      restored.deserialize(data)
      expect(restored.tenant_kit_gid).to eq(acme.to_global_id.to_s)
    end
  end

  it "performs a job under the tenant it was enqueued with" do
    TenantKit.with_tenant(acme) { TenantProbeJob.perform_later }
    perform_enqueued_jobs
    expect(TenantProbeJob::RESULTS).to eq([ acme.id ])
  end

  it "resets the tenant after the job finishes" do
    TenantKit.with_tenant(acme) { TenantProbeJob.perform_later }
    perform_enqueued_jobs
    expect(TenantKit::Current.tenant).to be_nil
  end

  context "when enqueued with no tenant" do
    it "performs without a tenant by default" do
      TenantProbeJob.perform_later
      perform_enqueued_jobs
      expect(TenantProbeJob::RESULTS).to eq([ nil ])
    end

    it "raises when raise_on_missing_job_tenant is true" do
      TenantKit.config.raise_on_missing_job_tenant = true
      TenantProbeJob.perform_later
      expect { perform_enqueued_jobs }.to raise_error(TenantKit::NoTenantSet)
    ensure
      TenantKit.config.raise_on_missing_job_tenant = false
    end
  end
end
