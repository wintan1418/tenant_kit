class DomainTenantsController < ApplicationController
  set_current_tenant_by_domain(:account, :domain)

  def show
    render plain: current_tenant&.name.to_s
  end
end
