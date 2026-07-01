module TenantKit
  # Holds the gem's configuration. Access the singleton via {TenantKit.config}
  # and set values in +config/initializers/tenant_kit.rb+ through
  # {TenantKit.configure}.
  #
  # @example
  #   TenantKit.configure do |config|
  #     config.tenant_class  = "Account"
  #     config.tenant_column = "account_id"
  #   end
  class Configuration
    # @return [String] name of the model that represents a tenant (e.g. "Account").
    attr_accessor :tenant_class

    # @return [String] foreign-key column on tenant-owned tables (e.g. "account_id").
    attr_accessor :tenant_column

    # @return [Boolean] strict mode: raise {NoTenantSet} when a tenant-scoped
    #   query runs with no current tenant (and not inside +without_tenant+).
    attr_accessor :require_tenant

    # @return [Boolean] carry the current tenant into ActiveJob background jobs.
    attr_accessor :propagate_to_jobs

    # @return [Boolean] raise if a job is performed with no captured tenant
    #   (only consulted when {#propagate_to_jobs} is true).
    attr_accessor :raise_on_missing_job_tenant

    def initialize
      @tenant_class                = "Account"
      @tenant_column               = "account_id"
      @require_tenant              = true
      @propagate_to_jobs           = true
      @raise_on_missing_job_tenant = false
    end

    # Resolves {#tenant_class} to the actual constant, lazily so it works with
    # Rails autoloading / reloading.
    #
    # @return [Class] the tenant model class.
    def tenant_model
      tenant_class.to_s.constantize
    end
  end
end
