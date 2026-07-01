# An owned model in the dummy host app declared with an explicit association.
class Invoice < ApplicationRecord
  belongs_to_tenant :account, class_name: "Account", foreign_key: "account_id"
  validates_uniqueness_to_tenant :number
end
