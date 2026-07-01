class SubdomainTenantsController < ApplicationController
  set_current_tenant_by_subdomain(:account, :subdomain)

  def show
    render plain: current_tenant&.name.to_s
  end
end
