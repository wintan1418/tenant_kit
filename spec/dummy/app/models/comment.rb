# Tenant-owned, polymorphic: can belong to a Project or a Task.
class Comment < ApplicationRecord
  belongs_to_tenant
  belongs_to :commentable, polymorphic: true
end
