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
                     "set raises rather than leaking another tenant's data. Optional PostgreSQL " \
                     "Row-Level Security adds database-enforced isolation underneath."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/wintan1418/tenant_kit/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/wintan1418/tenant_kit/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/wintan1418/tenant_kit/issues"
  spec.metadata["documentation_uri"] = "https://github.com/wintan1418/tenant_kit/tree/main/docs"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{lib}/**/*", "docs/**/*.md", "MIT-LICENSE", "Rakefile", "README.md", "CHANGELOG.md", "SECURITY.md", "llms.txt"]
  end

  # Runtime dependencies: Rails components only. No exotic deps.
  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
  spec.add_dependency "railties", ">= 7.2"
end
