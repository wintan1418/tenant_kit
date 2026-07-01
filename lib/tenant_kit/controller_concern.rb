module TenantKit
  # Mixed into +ActionController::Base+ and +ActionController::API+ (via the
  # railtie). Provides class-level helpers that install a +before_action+ to
  # resolve and set the current tenant for each request. +CurrentAttributes+
  # resets the tenant automatically between requests.
  module ControllerConcern
    extend ActiveSupport::Concern

    class_methods do
      # Resolves the tenant by request subdomain (+tenant.<field> == request.subdomain+).
      #
      # @param tenant_name [Symbol, nil] tenant model name (underscored). Defaults
      #   to the configured tenant class.
      # @param field [Symbol] the tenant column to match against. Default +:subdomain+.
      # @return [void]
      def set_current_tenant_by_subdomain(tenant_name = nil, field = :subdomain)
        model = TenantKit::ControllerConcern.tenant_model_for(tenant_name)
        before_action do
          self.current_tenant = model.find_by(field => request.subdomain)
        end
      end

      # Resolves the tenant by request host (+tenant.<field> == request.host+).
      #
      # @param tenant_name [Symbol, nil] tenant model name (underscored).
      # @param field [Symbol] the tenant column to match against. Default +:domain+.
      # @return [void]
      def set_current_tenant_by_domain(tenant_name = nil, field = :domain)
        model = TenantKit::ControllerConcern.tenant_model_for(tenant_name)
        before_action do
          self.current_tenant = model.find_by(field => request.host)
        end
      end

      # Resolves the tenant by an HTTP request header — for APIs.
      #
      # @param header [String] the header name, e.g. +"X-Tenant-Id"+.
      # @param tenant_name [Symbol, nil] tenant model name (underscored).
      # @param field [Symbol] the tenant column the header value maps to. Default +:id+.
      # @return [void]
      def set_current_tenant_by_header(header, tenant_name = nil, field = :id)
        model = TenantKit::ControllerConcern.tenant_model_for(tenant_name)
        before_action do
          value = request.headers[header]
          self.current_tenant = value && model.find_by(field => value)
        end
      end

      # Declares that the tenant is resolved by a custom +before_action+ the host
      # app defines. A no-op marker for readability — assign via +current_tenant=+
      # inside your own filter.
      #
      # @return [void]
      def set_current_tenant_through_filter
        # Intentionally empty: current_tenant= is always available.
      end
    end

    # Resolves the tenant model class for the given (optional) name.
    #
    # @param tenant_name [Symbol, String, nil]
    # @return [Class]
    def self.tenant_model_for(tenant_name)
      return TenantKit.config.tenant_model if tenant_name.nil?

      tenant_name.to_s.camelize.constantize
    end

    included do
      helper_method :current_tenant if respond_to?(:helper_method)
    end

    # @return [Object, nil] the current tenant for this request.
    def current_tenant
      TenantKit::Current.tenant
    end

    # Sets the current tenant for this request.
    #
    # @param tenant [Object, nil]
    # @return [Object, nil]
    def current_tenant=(tenant)
      TenantKit::Current.tenant = tenant
    end
  end
end
