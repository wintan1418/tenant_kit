require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Load the test schema fresh (force: true recreates every table).
ActiveRecord::Schema.verbose = false
require_relative "support/schema"

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Reset TenantKit's per-request state between examples so nothing bleeds.
  config.after(:each) do
    TenantKit::Current.reset if defined?(TenantKit::Current)
  end
end
