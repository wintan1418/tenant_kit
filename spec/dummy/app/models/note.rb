# Explicit-scoping-mode model: no tenant default_scope; callers opt in with
# Note.for_current_tenant, and the dev/test guard raises if they forget.
class Note < ApplicationRecord
  belongs_to_tenant scoping: :explicit
end
