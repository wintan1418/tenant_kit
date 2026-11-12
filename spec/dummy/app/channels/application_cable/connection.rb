module ApplicationCable
  # Resolves the tenant once per connection; TenantKit::Cable::Connection
  # re-establishes it around every channel command.
  class Connection < ActionCable::Connection::Base
    include TenantKit::Cable::Connection
    identified_by :current_tenant

    def connect
      self.current_tenant = Account.find_by(subdomain: request.subdomain) || reject_unauthorized_connection
    end
  end
end
