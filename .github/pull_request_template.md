## What and why

<!-- What does this change, and why? Link the issue. -->

## Checklist

- [ ] Specs cover the change (isolation behaviour in `spec/leaks/`)
- [ ] Defaults stay strict / fail-closed; anything more permissive is opt-in
- [ ] `docs/GUARANTEES.md` updated if guarantees changed
- [ ] `CHANGELOG.md` updated (with **Upgrade notes** for behaviour changes)
- [ ] `bundle exec rspec` and `bundle exec rubocop` pass (`DB=postgresql` too, if relevant)
