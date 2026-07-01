# An owned model in the dummy host app. Uses the default tenant association.
class Project < ApplicationRecord
  belongs_to_tenant
  validates_uniqueness_to_tenant :slug, allow_nil: true
end
