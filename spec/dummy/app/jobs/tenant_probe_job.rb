# Records the tenant that is current while the job runs, so specs can assert
# the enqueue-time tenant was re-established at perform time.
class TenantProbeJob < ApplicationJob
  RESULTS = []

  def perform
    RESULTS << TenantKit::Current.tenant&.id
  end
end
