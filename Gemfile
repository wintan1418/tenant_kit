source "https://rubygems.org"

# Specify your gem's dependencies in tenant_kit.gemspec.
gemspec

# Full Rails is a development/test dependency: the dummy host app under
# spec/dummy needs actionpack, activejob, etc. The gem itself only depends on
# activerecord/activesupport/railties (see tenant_kit.gemspec).
gem "rails", ">= 7.2"

gem "puma"

gem "sqlite3"

group :development, :test do
  gem "rspec-rails"
end

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
