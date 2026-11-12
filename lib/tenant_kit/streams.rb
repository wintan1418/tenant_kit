module TenantKit
  # Tenant-scoped stream names for Action Cable and Turbo Streams.
  #
  # A broadcast reaches everyone subscribed to its stream name, so a name built
  # only from a record (+"gid://app/Project/1"+) relies on every subscriber
  # having been authorized for that record. TenantKit puts the tenant first in
  # every name it builds (+"gid://app/Account/7:gid://app/Project/1"+), so a
  # stream can only be produced — and, with {TenantKit::Cable::Channel} or
  # {TenantKit::Turbo::StreamsChannel}, only be subscribed to — under its own
  # tenant.
  #
  # Names are built exactly the way turbo-rails builds them
  # (+Turbo::Streams::StreamName#stream_name_from+), so they interoperate with
  # +turbo_stream_from+ and +broadcast_*_to+.
  module Streams
    module_function

    # @param streamables [Array<Object>] records, strings or symbols.
    # @param tenant [Object] defaults to the current tenant.
    # @return [Array] +[tenant, *streamables]+.
    # @raise [NoTenantSet] when there is no tenant.
    def streamables(*streamables, tenant: TenantKit::Current.tenant)
      raise TenantKit::NoTenantSet, "A tenant stream needs a current tenant" if tenant.nil?

      [ tenant, *streamables ]
    end

    # @param streamables [Array<Object>] records, strings or symbols.
    # @param tenant [Object] defaults to the current tenant.
    # @return [String] the tenant-prefixed stream name.
    def stream_name(*streamables, tenant: TenantKit::Current.tenant)
      name_from(streamables(*streamables, tenant: tenant))
    end

    # @param name [String] a stream name.
    # @param tenant [Object]
    # @return [Boolean] true when +name+ was built for +tenant+.
    def tenant_stream?(name, tenant:)
      return false if tenant.nil? || name.nil?

      prefix = name_from(tenant)
      name == prefix || name.start_with?("#{prefix}:")
    end

    # Same algorithm as Turbo::Streams::StreamName#stream_name_from.
    #
    # @api private
    def name_from(streamables)
      if streamables.is_a?(Array)
        streamables.map { |streamable| name_from(streamable) }.join(":")
      else
        streamables.try(:to_gid_param) || streamables.to_param
      end
    end
  end
end
