# Tenant-owned child of Project, with a counter cache on the parent.
class Task < ApplicationRecord
  belongs_to_tenant
  belongs_to :project, counter_cache: true

  has_many :assignments, dependent: :destroy
  has_many :users, through: :assignments
  has_many :comments, as: :commentable
end
