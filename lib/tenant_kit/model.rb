module TenantKit
  # Mixed into every +ActiveRecord::Base+ (via the railtie). Provides the
  # +belongs_to_tenant+ macro that turns a plain model into a tenant-owned one:
  # it declares the tenant association, scopes all queries to the current tenant,
  # auto-assigns the tenant on create, and validates the tenant's presence.
  module Model
    extend ActiveSupport::Concern

    # Extended onto each tenant-owned model. Building a record evaluates the
    # strict +default_scope+ via +scope_for_create+; without this guard,
    # +Model.new+ with no current tenant would raise instead of letting presence
    # validation report the missing tenant. We disable scoping only for the build
    # itself — the subsequent +save+ (and its validations) runs normally.
    module BuildGuard
      def new(*args, **kwargs, &block)
        TenantKit.without_tenant { super }
      end
    end

    class_methods do
      # Declares this model as tenant-owned.
      #
      # @param association [Symbol, nil] the tenant association name. Defaults to
      #   the underscored {TenantKit::Configuration#tenant_class} (e.g. +:account+).
      # @param options [Hash] forwarded to +belongs_to+ (+:class_name+,
      #   +:foreign_key+, +:optional+, +:inverse_of+, ...).
      # @option options [String] :foreign_key overrides
      #   {TenantKit::Configuration#tenant_column}.
      # @return [void]
      #
      # @example Default tenant
      #   class Project < ApplicationRecord
      #     belongs_to_tenant
      #   end
      #
      # @example Explicit association
      #   class Invoice < ApplicationRecord
      #     belongs_to_tenant :account, class_name: "Account", foreign_key: "account_id"
      #   end
      def belongs_to_tenant(association = nil, **options)
        assoc = (association || TenantKit.config.tenant_class.underscore).to_sym
        fk    = (options[:foreign_key] || TenantKit.config.tenant_column).to_s

        self._tenant_kit_association = assoc
        self._tenant_kit_foreign_key = fk

        extend TenantKit::Model::BuildGuard

        belongs_to assoc, **options.slice(:class_name, :foreign_key, :optional, :inverse_of)

        # Scope every read to the current tenant. Strict by default: querying with
        # no tenant (and not inside without_tenant) raises rather than leaking.
        default_scope do
          if TenantKit.scoping_active?
            where(fk => TenantKit::Current.tenant.public_send(:id))
          elsif TenantKit.config.require_tenant && !TenantKit.scoping_disabled?
            raise TenantKit::NoTenantSet, "No current tenant set for #{name}"
          else
            all
          end
        end

        # Auto-assign the tenant on new records via before_validation — never via
        # default_scope create behavior, which is a known foot-gun.
        before_validation do
          if TenantKit::Current.tenant && public_send(assoc).nil?
            public_send("#{assoc}=", TenantKit::Current.tenant)
          end
        end

        validates assoc, presence: true, unless: -> { TenantKit.scoping_disabled? }
      end

      # Validates that +attrs+ are unique within the current tenant, allowing the
      # same value to reappear under a different tenant. The tenant foreign key is
      # always folded into the uniqueness scope, so this must be called after
      # {#belongs_to_tenant}.
      #
      # @param attrs [Array<Symbol>] attributes to check.
      # @param opts [Hash] forwarded to the underlying uniqueness validation
      #   (+:scope+, +:case_sensitive+, +:message+, +:conditions+, ...).
      # @return [void]
      def validates_uniqueness_to_tenant(*attrs, **opts)
        unless _tenant_kit_foreign_key
          raise ArgumentError, "call belongs_to_tenant before validates_uniqueness_to_tenant"
        end

        scope = (Array(opts[:scope]) + [ _tenant_kit_foreign_key.to_sym ]).uniq
        validates_uniqueness_of(*attrs, **opts.merge(scope: scope))
      end
    end

    included do
      # The tenant association name and foreign key, set by belongs_to_tenant.
      class_attribute :_tenant_kit_association, instance_accessor: false, default: nil
      class_attribute :_tenant_kit_foreign_key, instance_accessor: false, default: nil
    end
  end
end
