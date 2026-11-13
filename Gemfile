source "https://rubygems.org"

# Specify your gem's dependencies in tenant_kit.gemspec.
gemspec

# Full Rails is a development/test dependency: the dummy host app under
# spec/dummy needs actionpack, activejob, etc. The gem itself only depends on
# activerecord/activesupport/railties (see tenant_kit.gemspec).
#
# The CI matrix pins a Rails series through gemfiles/rails_*.gemfile
# (BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rspec).
gem "rails", ENV.fetch("RAILS_VERSION", ">= 7.2")

eval_gemfile "gemfiles/common.gemfile"
