if ENV.fetch("COVERAGE", "true") != "false"
  require "simplecov"
  SimpleCov.start do
    # Each CI job (Ruby x Rails x database) must meet the threshold on its own.
    use_merging false
    enable_coverage :branch
    add_filter "/spec/"
    add_filter "/gemfiles/"
    track_files "lib/**/*.rb"
    command_name "#{ENV.fetch("DB", "sqlite")}-rails#{ENV.fetch("BUNDLE_GEMFILE", "default")[/rails_(\d_\d)/, 1] || "default"}"
    minimum_coverage line: Integer(ENV.fetch("MIN_COVERAGE", "90"))
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
