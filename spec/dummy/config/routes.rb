Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Routes exercising the TenantKit controller resolution helpers.
  get "by_subdomain" => "subdomain_tenants#show"
  get "by_domain"    => "domain_tenants#show"
  get "by_header"    => "header_tenants#show"
end
