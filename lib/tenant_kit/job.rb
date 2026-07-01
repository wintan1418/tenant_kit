require "global_id"

module TenantKit
  # Mixed into +ActiveJob::Base+ (via the railtie, when
  # +config.propagate_to_jobs+ is true) so a job runs under the same tenant it
  # was enqueued under — even though it executes later, in another process, with
  # no request context.
  #
  # The tenant's GlobalID is captured at enqueue time and folded into the job's
  # serialized payload (not just an in-memory attribute), so it survives any
  # ActiveJob queue adapter — Solid Queue included — and is re-established around
  # +perform+.
  module Job
    extend ActiveSupport::Concern

    included do
      # @return [String, nil] the enqueued tenant's GlobalID URI.
      attr_accessor :tenant_kit_gid

      around_enqueue do |job, block|
        job.tenant_kit_gid ||= TenantKit::Current.tenant&.to_global_id&.to_s
        block.call
      end

      around_perform do |job, block|
        if job.tenant_kit_gid
          tenant = GlobalID::Locator.locate(job.tenant_kit_gid)
          TenantKit.with_tenant(tenant) { block.call }
        elsif TenantKit.config.raise_on_missing_job_tenant
          raise TenantKit::NoTenantSet, "Job #{job.class} enqueued without a tenant"
        else
          block.call
        end
      end
    end

    # Folds the captured tenant GlobalID into the serialized job payload so it
    # round-trips through the queue adapter.
    #
    # @return [Hash]
    def serialize
      super.merge("tenant_kit_gid" => tenant_kit_gid)
    end

    # Restores the captured tenant GlobalID when the job is deserialized for
    # execution.
    #
    # @param job_data [Hash]
    # @return [void]
    def deserialize(job_data)
      super
      self.tenant_kit_gid = job_data["tenant_kit_gid"]
    end
  end
end
