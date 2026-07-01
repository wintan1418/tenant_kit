require_relative "lib/tenant_kit/version"

Gem::Specification.new do |spec|
  spec.name        = "tenant_kit"
  spec.version     = TenantKit::VERSION
  spec.authors     = [ "wintan1418" ]
  spec.email       = [ "wintan1418@gmail.com" ]
  spec.homepage    = "https://github.com/wintan1418/tenant_kit"
  spec.summary     = "Row-level (shared-schema) multi-tenancy for Rails, strict by default, with background-job tenant propagation."
  spec.description = "TenantKit makes a Rails app multi-tenant using the row-level / shared-schema " \
                     "strategy: one database, a tenant_id foreign key on owned tables, automatic " \
                     "query scoping via ActiveSupport::CurrentAttributes, auto-assignment of the " \
                     "current tenant, and first-class tenant propagation into ActiveJob background " \
                     "jobs. It is strict by default: querying a tenant-scoped model with no tenant " \
                     "set raises rather than leaking another tenant's data."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/wintan1418/tenant_kit"
  spec.metadata["changelog_uri"] = "https://github.com/wintan1418/tenant_kit/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  # Runtime dependencies: Rails components only. No exotic deps.
  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
  spec.add_dependency "railties", ">= 7.2"
end
