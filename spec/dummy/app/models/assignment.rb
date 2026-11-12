# Tenant-owned join model between a global User and a tenant-owned Task.
class Assignment < ApplicationRecord
  belongs_to_tenant
  belongs_to :user
  belongs_to :task
end
