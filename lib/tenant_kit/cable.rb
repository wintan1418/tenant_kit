module TenantKit
  # Action Cable integration. Action Cable commands (subscribe, unsubscribe,
  # channel actions) run outside any request, so +TenantKit::Current+ is empty
  # unless the connection re-establishes the tenant for each command.
  #
  # @example
  #   module ApplicationCable
  #     class Connection < ActionCable::Connection::Base
  #       include TenantKit::Cable::Connection
  #       identified_by :current_tenant
  #
  #       def connect
  #         self.current_tenant = Account.find_by!(subdomain: request.subdomain)
  #       end
  #     end
  #
  #     class Channel < ActionCable::Channel::Base
  #       include TenantKit::Cable::Channel
  #     end
  #   end
  #
  #   class ProjectChannel < ApplicationCable::Channel
  #     def subscribed
  #       project = Project.find(params[:id])      # scoped: other tenants' ids 404
  #       stream_for_tenant project
  #     end
  #   end
  #
  #   ProjectChannel.broadcast_to_tenant(project.account, project, html: "...")
  module Cable
    # Include in +ApplicationCable::Connection+. Runs every channel command
    # under the connection's +current_tenant+.
    module Connection
      extend ActiveSupport::Concern

      included do
        around_command :tenant_kit_around_command
      end

      private

      def tenant_kit_around_command(&block)
        tenant = respond_to?(:current_tenant) ? current_tenant : nil
        tenant ? TenantKit.with_tenant(tenant, &block) : yield
      end
    end

    # Include in +ApplicationCable::Channel+ for tenant-prefixed streams.
    module Channel
      extend ActiveSupport::Concern

      class_methods do
        # Broadcasts +message+ on the tenant-scoped stream for +model+.
        #
        # @param tenant [Object]
        # @param model [Object] record (or any object stream_for accepts).
        # @param message [Hash]
        def broadcast_to_tenant(tenant, model, message)
          broadcast_to(TenantKit::Streams.streamables(model, tenant: tenant), message)
        end

        # @return [String] the broadcasting name for +model+ under +tenant+.
        def tenant_broadcasting_for(tenant, model)
          broadcasting_for(TenantKit::Streams.streamables(model, tenant: tenant))
        end
      end

      private

      # The subscriber's tenant: the connection's +current_tenant+ identifier
      # when it has one, otherwise {TenantKit::Current.tenant}.
      #
      # @return [Object, nil]
      def subscriber_tenant
        TenantKit::Cable.subscriber_tenant(connection)
      end

      # Streams +model+ under the subscriber's tenant. Rejects the subscription
      # when there is no tenant, or when +model+ is a tenant-owned record of
      # another tenant.
      #
      # @return [Boolean] whether the stream was started.
      def stream_for_tenant(model, ...)
        tenant = subscriber_tenant
        unless tenant && tenant_kit_owned_by?(model, tenant)
          reject
          return false
        end

        stream_for(TenantKit::Streams.streamables(model, tenant: tenant), ...)
        true
      end

      # Rejects the subscription unless +record+ belongs to the subscriber's
      # tenant.
      #
      # @return [Boolean] true when the subscription was rejected.
      def reject_unless_current_tenant_owns(record)
        tenant = subscriber_tenant
        return false if tenant && tenant_kit_owned_by?(record, tenant)

        reject
        true
      end

      def tenant_kit_owned_by?(record, tenant)
        klass = record.class
        return true unless klass.respond_to?(:tenant_owned?) && klass.tenant_owned?

        record[klass._tenant_kit_foreign_key].to_s == tenant.id.to_s
      end
    end

    # @api private
    def self.subscriber_tenant(connection)
      from_connection = connection.current_tenant if connection.respond_to?(:current_tenant)
      from_connection || TenantKit::Current.tenant
    end
  end
end
