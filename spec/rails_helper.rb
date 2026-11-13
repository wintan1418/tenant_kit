require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "dummy/config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Create the test database on first run for server databases (PostgreSQL,
# MySQL); SQLite creates its file on connect.
begin
  ActiveRecord::Base.connection.verify!
rescue ActiveRecord::NoDatabaseError
  ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.connection_db_config)
  ActiveRecord::Base.establish_connection
end

# Load the test schema fresh (every table is dropped and recreated).
ActiveRecord::Schema.verbose = false
require_relative "support/schema"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each do |file|
  require file unless file.end_with?("schema.rb")
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Database-specific examples: `postgresql: true` runs only on DB=postgresql.
  adapter = ActiveRecord::Base.connection.adapter_name.downcase
  config.filter_run_excluding postgresql: true unless adapter.include?("postg")

  # Reset TenantKit's per-request state between examples so nothing bleeds.
  config.after(:each) do
    TenantKit::Current.reset if defined?(TenantKit::Current)
  end
end
