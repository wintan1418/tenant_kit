module TenantKit
  # Turbo Streams integration (requires the turbo-rails gem in the host app).
  #
  # @example Model: broadcasts go to a stream that starts with the record's tenant
  #   class Project < ApplicationRecord
  #     belongs_to_tenant
  #     broadcasts_to_tenant                 # stream: [project.account, "projects"]
  #   end
  #
  # @example View: subscribe to the matching stream for the current tenant
  #   <%= turbo_stream_from_tenant "projects" %>
  #
  # @example Channel: refuse subscriptions to other tenants' streams
  #   class TenantStreamsChannel < Turbo::StreamsChannel
  #     include TenantKit::Turbo::StreamsChannel
  #   end
  #   <%= turbo_stream_from_tenant "projects", channel: TenantStreamsChannel %>
  module Turbo
    # Class macros extended onto ActiveRecord::Base by the railtie.
    module Broadcasts
      # Like Turbo's +broadcasts_to+, but:
      #
      # * the stream is always prefixed with the record's own tenant, so a
      #   broadcast can never land on another tenant's stream, and
      # * the broadcast is enqueued under the record's tenant, so the
      #   background render runs scoped to it — even when the record was
      #   saved inside +without_tenant+ (seeds, admin tools).
      #
      # Creates append (or +inserts_by+), updates replace, destroys remove —
      # the same callbacks as +broadcasts_to+.
      #
      # @param stream [Symbol, Proc, String, nil] the rest of the stream: a
      #   method name, a +->(record) { ... }+, a fixed string, or +nil+ for the
      #   pluralized model name (what +broadcasts+ uses).
      # @param inserts_by [Symbol] Turbo Stream action for creates.
      # @param target [String, Proc, nil] DOM target for creates (default:
      #   the pluralized model name).
      # @param rendering [Hash] forwarded to the broadcast (+:partial+, +:locals+, ...).
      def broadcasts_to_tenant(stream = nil, inserts_by: :append, target: nil, **rendering)
        unless method_defined?(:broadcast_action_later_to)
          raise TenantKit::Error, "broadcasts_to_tenant requires turbo-rails"
        end
        unless respond_to?(:tenant_owned?) && tenant_owned?
          raise ArgumentError, "call belongs_to_tenant before broadcasts_to_tenant"
        end

        streams = ->(record) { record.tenant_stream(*TenantKit::Turbo.resolve_stream(record, stream)) }
        targets = ->(record) { (target.respond_to?(:call) ? target.call(record) : target) || record.model_name.plural }

        after_create_commit lambda {
          _tenant_kit_as_own_tenant do
            broadcast_action_later_to(streams.call(self), action: inserts_by, target: targets.call(self), **rendering)
          end
        }
        after_update_commit lambda {
          _tenant_kit_as_own_tenant { broadcast_replace_later_to(streams.call(self), **rendering) }
        }
        after_destroy_commit lambda {
          _tenant_kit_as_own_tenant { broadcast_remove_to(streams.call(self)) }
        }
      end
    end

    # Instance helper included into ActiveRecord::Base by the railtie.
    module Record
      # @return [Array] +[tenant, *streamables]+ using this record's own tenant.
      def tenant_stream(*streamables)
        TenantKit::Streams.streamables(*streamables, tenant: public_send(self.class._tenant_kit_association))
      end

      private

      # Runs the block under this record's own tenant.
      def _tenant_kit_as_own_tenant(&block)
        TenantKit.with_tenant(public_send(self.class._tenant_kit_association), &block)
      end
    end

    # View helpers included into ActionView by the railtie.
    module Helper
      # +turbo_stream_from+ for the current tenant's stream.
      def turbo_stream_from_tenant(*streamables, **attributes)
        turbo_stream_from(TenantKit::Streams.streamables(*streamables), **attributes)
      end

      # @return [String] the current tenant's stream name for +streamables+.
      def tenant_stream_name(*streamables)
        TenantKit::Streams.stream_name(*streamables)
      end
    end

    # Include in a subclass of +Turbo::StreamsChannel+. Subscriptions are
    # accepted only for verified (signed) stream names that start with the
    # subscriber's tenant — the connection's +current_tenant+ identifier, or
    # the current tenant (pair with {TenantKit::Cable::Connection}).
    module StreamsChannel
      def subscribed
        name = verified_stream_name_from_params
        if name.present? && TenantKit::Streams.tenant_stream?(name, tenant: TenantKit::Cable.subscriber_tenant(connection))
          stream_from name
        else
          reject
        end
      end
    end

    # @api private
    def self.resolve_stream(record, stream)
      case stream
      when nil then [ record.model_name.plural ]
      when Symbol then Array(record.public_send(stream))
      when Proc then Array(stream.call(record))
      else Array(stream)
      end
    end
  end
end
