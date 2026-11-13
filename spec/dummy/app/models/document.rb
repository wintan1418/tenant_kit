# STI base class. Subclasses inherit the tenant scope.
class Document < ApplicationRecord
  belongs_to_tenant
  broadcasts_to_tenant
end
