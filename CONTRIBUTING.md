# Contributing to TenantKit

Thanks for helping! TenantKit guards a security boundary, so the bar for
changes is: **every behaviour is pinned by a spec, and every isolation claim is
listed in [docs/GUARANTEES.md](docs/GUARANTEES.md).**

> Found a way to read or write another tenant's data? Please **don't** open an
> issue — report it privately (see [SECURITY.md](SECURITY.md)).

## Getting started

```bash
git clone https://github.com/wintan1418/tenant_kit && cd tenant_kit
bundle install
bundle exec rspec          # SQLite, newest Rails
bundle exec rubocop
```

The suite runs against a dummy Rails app in `spec/dummy` and loads its schema
from `spec/support/schema.rb` on every run.

### Other databases and Rails versions

```bash
DB=postgresql bundle exec rspec        # needs a local PostgreSQL (libpq env vars, or DB_HOST/DB_USERNAME/DB_PASSWORD)
DB=mysql bundle exec rspec             # needs a local MySQL 8 (DB_HOST, DB_USERNAME, DB_PASSWORD)

BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile DB=postgresql bundle exec rspec

bin/matrix                              # every Rails gemfile x sqlite,postgresql
DBS="sqlite postgresql mysql" bin/matrix
```

The test database is created automatically. PostgreSQL-only specs (Row-Level
Security) are tagged `postgresql: true` and skipped elsewhere; they create a
`tenant_kit_rls_app` role, so the PostgreSQL user needs `CREATEROLE` (a local
superuser is fine).

CI runs Ruby 3.3 and 3.4 × Rails 7.2, 8.0 and 8.1 × SQLite, PostgreSQL and
MySQL, plus RuboCop and a gem build. Line coverage must stay at or above 90% in
each job (`MIN_COVERAGE`); set `COVERAGE=false` to skip SimpleCov locally.

## Making a change

1. Open an issue first for anything beyond a small fix, so we can agree on the
   approach.
2. Write the failing spec first. Isolation behaviour belongs in `spec/leaks/`
   and uses the `"two tenants"` shared context: act as tenant A, attack
   tenant B.
3. Keep the default behaviour strict and fail-closed. New permissive behaviour
   must be opt-in.
4. If you change what is or isn't guaranteed, update
   [docs/GUARANTEES.md](docs/GUARANTEES.md) (with the spec reference) and the
   README.
5. Add a line to `CHANGELOG.md` under **Unreleased** — and an **Upgrade notes**
   entry for anything that changes behaviour for existing users.
6. `bundle exec rspec && bundle exec rubocop` must pass.

## Style

- RuboCop with [rubocop-rails-omakase](https://github.com/rails/rubocop-rails-omakase).
- No runtime dependencies beyond `activerecord`, `activesupport` and `railties`.
  Optional integrations (Turbo, Action Cable, PostgreSQL) must not require
  their gems at load time.
- Prefer public Rails APIs. When a private Rails API is unavoidable (e.g. the
  PostgreSQL adapter hook), cover it on every supported Rails version and say
  so in a comment.
- Short, imperative commit messages ("Guard update_counters against foreign ids").

## Releasing (maintainer)

See the release checklist in [AGENTS.md](AGENTS.md#releasing).

By contributing you agree that your contributions are licensed under the MIT
License and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
