# Fails on its first attempt, then records the tenant it ran under — proves a
# retried job keeps the tenant it was first enqueued with.
class FlakyTenantJob < ApplicationJob
  class Flake < StandardError; end
  ATTEMPTS = []

  retry_on Flake, wait: 0, attempts: 3

  def perform
    ATTEMPTS << TenantKit::Current.tenant&.id
    raise Flake if ATTEMPTS.size == 1
  end
end
