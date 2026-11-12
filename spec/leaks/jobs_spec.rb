require "rails_helper"

# Background work: the tenant must ride along with jobs and mailers, survive
# retries, and never let a job act on another tenant's record.
RSpec.describe "Leak suite: jobs and mailers", type: :job do
  include ActiveJob::TestHelper
  include_context "two tenants"

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    [ ProjectNameJob::RESULTS, FlakyTenantJob::ATTEMPTS, TenantProbeJob::RESULTS ].each(&:clear)
    ActionMailer::Base.deliveries.clear
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  describe "record arguments" do
    it "deserializes a tenant-owned argument and performs under the enqueuing tenant" do
      as_acme { ProjectNameJob.perform_later(Project.find(mine[:project].id)) }
      perform_enqueued_jobs
      expect(ProjectNameJob::RESULTS).to eq([ [ acme.id, "Acme project", 1 ] ])
    end

    it "raises TenantMismatch when handed another tenant's record" do
      foreign = TenantKit.without_tenant { Project.find(theirs[:project].id) }
      as_acme { ProjectNameJob.perform_later(foreign) }
      expect { perform_enqueued_jobs }.to raise_error(TenantKit::TenantMismatch)
      expect(ProjectNameJob::RESULTS).to be_empty
    end

    it "checks records nested in arrays and hashes" do
      foreign = TenantKit.without_tenant { Project.find(theirs[:project].id) }
      as_acme { ProjectNameJob.perform_later(mine[:project], { "others" => [ foreign ] }) }
      expect { perform_enqueued_jobs }.to raise_error(TenantKit::TenantMismatch)
    end

    it "can be turned off with verify_job_arguments = false" do
      TenantKit.config.verify_job_arguments = false
      foreign = TenantKit.without_tenant { Project.find(theirs[:project].id) }
      as_acme { ProjectNameJob.perform_later(foreign) }
      perform_enqueued_jobs
      expect(ProjectNameJob::RESULTS.first.first(2)).to eq([ acme.id, "Globex project" ])
    ensure
      TenantKit.config.verify_job_arguments = true
    end
  end

  describe "retries" do
    it "a retried job keeps the tenant it was first enqueued with" do
      as_acme { FlakyTenantJob.perform_later }
      perform_enqueued_jobs
      perform_enqueued_jobs
      expect(FlakyTenantJob::ATTEMPTS).to eq([ acme.id, acme.id ])
    end

    it "the retry payload carries the original tenant even if enqueued from elsewhere" do
      job = as_acme { FlakyTenantJob.perform_later }
      expect(enqueued_jobs.last["tenant_kit_gid"]).to eq(acme.to_global_id.to_s)
      expect(job.tenant_kit_gid).to eq(acme.to_global_id.to_s)
    end
  end

  describe "perform_now" do
    it "runs inline under the caller's tenant" do
      as_acme { TenantProbeJob.perform_now }
      expect(TenantProbeJob::RESULTS).to eq([ acme.id ])
    end

    it "raises with raise_on_missing_job_tenant and no tenant anywhere" do
      TenantKit.config.raise_on_missing_job_tenant = true
      expect { TenantProbeJob.perform_now }.to raise_error(TenantKit::NoTenantSet)
    ensure
      TenantKit.config.raise_on_missing_job_tenant = false
    end

    it "a deserialized job runs under its captured tenant, not the caller's" do
      payload = as_acme { TenantProbeJob.new.tap { |j| j.run_callbacks(:enqueue) { } }.serialize }
      TenantKit.with_tenant(globex) { ActiveJob::Base.execute(payload) }
      expect(TenantProbeJob::RESULTS).to eq([ acme.id ])
    end

    it "a job enqueued inside without_tenant with a tenant set still runs scoped" do
      as_acme { TenantKit.without_tenant { ProjectNameJob.perform_later(mine[:project]) } }
      perform_enqueued_jobs
      expect(ProjectNameJob::RESULTS.first.last).to eq(1)
    end
  end

  describe "mailers via deliver_later" do
    it "render under the tenant that enqueued them" do
      as_acme { ProjectMailer.summary.deliver_later }
      expect(TenantKit::Current.tenant).to be_nil
      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("Projects for Acme")
      expect(mail.body.encoded).to include("Acme project")
      expect(mail.body.encoded).not_to include("Globex project")
    end

    it "refuse another tenant's record as a mailer argument" do
      foreign = TenantKit.without_tenant { Project.find(theirs[:project].id) }
      as_acme { ProjectMailer.summary(foreign).deliver_later }
      expect { perform_enqueued_jobs }.to raise_error(TenantKit::TenantMismatch)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
