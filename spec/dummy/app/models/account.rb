# The tenant model for the dummy host app.
#
# The tenant table is a normal model — it does NOT call belongs_to_tenant.
class Account < ApplicationRecord
  has_many :projects
  has_many :invoices
end
