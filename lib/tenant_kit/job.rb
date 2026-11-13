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
  # +perform_now+: argument deserialization, every +perform+ callback, and
  # +perform+ itself run under the tenant. Retries (+retry_on+) re-enqueue with
  # the same captured tenant.
  #
  # GlobalID locates records with +unscoped+, so a job argument is never
  # filtered by tenant scoping. With +config.verify_job_arguments+ (default
  # +true+) TenantKit checks every deserialized tenant-owned record argument
  # (including inside arrays and hashes) belongs to the job's tenant and raises
  # {TenantMismatch} otherwise.
  module Job
    extend ActiveSupport::Concern

    included do
      # @return [String, nil] the enqueued tenant's GlobalID URI.
      attr_accessor :tenant_kit_gid

      around_enqueue do |job, block|
        job.tenant_kit_gid ||= TenantKit::Current.tenant&.to_global_id&.to_s
        block.call
      end

      before_perform :tenant_kit_verify_arguments
    end

    # Runs the job under its captured tenant. A job with no captured tenant
    # (e.g. +perform_now+ called inline) runs under whatever tenant is current,
    # or raises when +config.raise_on_missing_job_tenant+ is set and there is
    # none.
    #
    # @return [Object] the job's result.
    def perform_now
      if tenant_kit_gid
        tenant = TenantKit.without_tenant { GlobalID::Locator.locate(tenant_kit_gid) }
        raise TenantKit::NoTenantSet, "Job #{self.class} tenant #{tenant_kit_gid} could not be found" if tenant.nil?

        TenantKit.with_tenant(tenant) { super }
      elsif TenantKit.config.raise_on_missing_job_tenant && TenantKit::Current.tenant.nil?
        raise TenantKit::NoTenantSet, "Job #{self.class} enqueued without a tenant"
      else
        super
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

    private

    def tenant_kit_verify_arguments
      return unless TenantKit.config.verify_job_arguments && TenantKit.scoping_active?

      tenant_id = TenantKit.current_tenant_id.to_s
      tenant_kit_each_record(arguments) do |record|
        next unless record.class.respond_to?(:tenant_owned?) && record.class.tenant_owned?

        owner = record[record.class._tenant_kit_foreign_key]
        next if owner.nil? || owner.to_s == tenant_id

        raise TenantKit::TenantMismatch,
          "Job #{self.class} runs under tenant #{tenant_id} but was given #{record.class.name}##{record.id} " \
          "of tenant #{owner}"
      end
    end

    def tenant_kit_each_record(value, &block)
      case value
      when ActiveRecord::Base then yield value
      when Array then value.each { |item| tenant_kit_each_record(item, &block) }
      when Hash then value.each_value { |item| tenant_kit_each_record(item, &block) }
      end
    end
  end
end
