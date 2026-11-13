# A global (non-tenant) model. Reaching tenant-owned rows through it is still
# subject to tenant scoping on the owned side.
class User < ApplicationRecord
  has_many :assignments
  has_many :tasks, through: :assignments
end
