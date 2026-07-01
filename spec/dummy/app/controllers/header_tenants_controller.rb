class HeaderTenantsController < ApplicationController
  set_current_tenant_by_header("X-Tenant-Id")

  def show
    render plain: current_tenant&.name.to_s
  end
end
