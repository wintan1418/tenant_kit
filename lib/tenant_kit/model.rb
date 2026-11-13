module TenantKit
  # Mixed into every +ActiveRecord::Base+ (via the railtie). Provides the
  # +belongs_to_tenant+ macro that turns a plain model into a tenant-owned one:
  # it declares the tenant association, scopes all queries to the current tenant,
  # auto-assigns the tenant on create, validates the tenant's presence, and
  # refuses writes that would move a row into (or out of) another tenant.
  module Model
    extend ActiveSupport::Concern

    SCOPING_MODES = %i[default explicit].freeze

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

    # Extended onto each tenant-owned model. Rails implements
    # +update_counters+ (and so +increment_counter+ / +decrement_counter+) on
    # +unscoped+, so an id from another tenant would be updated. Route it
    # through the tenant scope instead.
    module CounterGuard
      def update_counters(id, counters)
        return super if TenantKit.scoping_disabled?

        _tenant_kit_scope.where(primary_key => id).update_counters(counters)
      end
    end

    # Prepended onto +ActiveRecord::InsertAll+, which backs +insert+,
    # +insert!+, +insert_all+, +insert_all!+, +upsert+ and +upsert_all+ on
    # models and relations alike. For tenant-owned models it fills in the
    # current tenant on rows that omit it and raises {CrossTenantWrite} for
    # rows that name another tenant; with no tenant set it raises
    # {NoTenantSet} under strict mode.
    module InsertAllGuard
      def initialize(relation, connection, inserts, **options)
        model = relation.model
        inserts = TenantKit::Model.tenant_rows(model, inserts) if model.respond_to?(:tenant_owned?) && model.tenant_owned?
        super(relation, connection, inserts, **options)
      end
    end

    # Rewrites rows passed to +insert_all+ / +upsert_all+ so each one carries
    # the current tenant, raising when a row names a different tenant.
    #
    # @api private
    def self.tenant_rows(model, rows)
      return rows if TenantKit.scoping_disabled?

      tenant_id = TenantKit.current_tenant_id
      if tenant_id.nil?
        raise TenantKit::NoTenantSet, "No current tenant set for #{model.name}" if TenantKit.config.require_tenant

        return rows
      end

      fk = model._tenant_kit_foreign_key
      Array(rows).map do |row|
        row = row.to_h.transform_keys(&:to_s)
        if row.key?(fk) && row[fk].to_s != tenant_id.to_s
          raise TenantKit::CrossTenantWrite,
            "#{model.name} row names #{fk}=#{row[fk].inspect} but the current tenant is #{tenant_id.inspect}"
        end
        row.merge(fk => tenant_id)
      end
    end

    class_methods do
      # Declares this model as tenant-owned.
      #
      # @param association [Symbol, nil] the tenant association name. Defaults to
      #   the underscored {TenantKit::Configuration#tenant_class} (e.g. +:account+).
      # @param scoping [Symbol] +:default+ (the tenant condition is a strict
      #   +default_scope+) or +:explicit+ (no +default_scope+; call
      #   +for_current_tenant+ at each call site, with a dev/test guard that
      #   raises when you forget). See {TenantKit::ExplicitScoping}.
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
      #
      # @example Explicit scoping mode
      #   class Note < ApplicationRecord
      #     belongs_to_tenant scoping: :explicit
      #   end
      #   Note.for_current_tenant.where(pinned: true)
      def belongs_to_tenant(association = nil, scoping: :default, **options)
        unless SCOPING_MODES.include?(scoping)
          raise ArgumentError, "belongs_to_tenant scoping: must be one of #{SCOPING_MODES.inspect}, got #{scoping.inspect}"
        end

        assoc = (association || TenantKit.config.tenant_class.underscore).to_sym
        fk    = (options[:foreign_key] || TenantKit.config.tenant_column).to_s

        self._tenant_kit_association = assoc
        self._tenant_kit_foreign_key = fk
        self._tenant_kit_scoping     = scoping

        extend TenantKit::Model::BuildGuard
        singleton_class.prepend TenantKit::Model::CounterGuard

        belongs_to assoc, **options.slice(:class_name, :foreign_key, :optional, :inverse_of)

        if scoping == :explicit
          TenantKit::ExplicitScoping.install(self)
        else
          # Scope every read to the current tenant. Strict by default: querying
          # with no tenant (and not inside without_tenant) raises rather than
          # leaking. With config.scope_record_writes the same condition is added
          # to the UPDATE/DELETE that record#save / #destroy / #update_columns run.
          default_scope(all_queries: TenantKit.config.scope_record_writes || nil) do
            if TenantKit.scoping_active?
              where(klass._tenant_kit_predicate(TenantKit.current_tenant_id))
            elsif TenantKit.config.require_tenant && !TenantKit.scoping_disabled?
              raise TenantKit::NoTenantSet, "No current tenant set for #{klass.name}"
            else
              all
            end
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
        validate :_tenant_kit_validate_tenant_write
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

      # @return [Boolean] true when this model was declared with +belongs_to_tenant+.
      def tenant_owned?
        !_tenant_kit_foreign_key.nil?
      end

      # Builds the tenant condition as a {TenantKit::TenantPredicate} so that
      # association scopes, +merge+, +rewhere+ and +unscope(where:)+ cannot
      # replace it.
      #
      # @api private
      def _tenant_kit_predicate(tenant_id)
        node = predicate_builder.build(arel_table[_tenant_kit_foreign_key], tenant_id)
        TenantKit::TenantPredicate.new(node.left, node.right)
      end

      # The relation that represents "this tenant's rows" for the model's
      # scoping mode.
      #
      # @api private
      def _tenant_kit_scope
        _tenant_kit_scoping == :explicit ? for_current_tenant : all
      end
    end

    included do
      # The tenant association name, foreign key and scoping mode, set by
      # belongs_to_tenant.
      class_attribute :_tenant_kit_association, instance_accessor: false, default: nil
      class_attribute :_tenant_kit_foreign_key, instance_accessor: false, default: nil
      class_attribute :_tenant_kit_scoping, instance_accessor: false, default: nil
    end

    private

    # Refuses writes that would move a row across a tenant boundary:
    #
    # * a persisted record's tenant foreign key may not change (outside
    #   +without_tenant+), and
    # * while a tenant is current, a record may only be saved under that tenant —
    #   so a mass-assigned +account_id+ from request params cannot plant a row in
    #   another tenant.
    #
    # Both are skipped inside {TenantKit.without_tenant} and when
    # +config.prevent_cross_tenant_writes+ is false.
    def _tenant_kit_validate_tenant_write
      return unless TenantKit.config.prevent_cross_tenant_writes
      return if TenantKit.scoping_disabled?

      assoc = self.class._tenant_kit_association
      fk    = self.class._tenant_kit_foreign_key

      if persisted? && will_save_change_to_attribute?(fk)
        errors.add(assoc, :tenant_kit_changed, message: "cannot be changed to another tenant")
      elsif TenantKit.scoping_active? && !self[fk].nil? && self[fk].to_s != TenantKit.current_tenant_id.to_s
        errors.add(assoc, :tenant_kit_mismatch, message: "must be the current tenant")
      end
    end
  end

  # The tenant condition TenantKit adds to every scoped query.
  #
  # It renders exactly like a normal equality (+"projects"."account_id" = $1+),
  # and still shows up in +where_values_hash+ (so +insert_all+ and
  # +scope_for_create+ see the tenant). What it does *not* do is report its
  # column through +fetch_attribute+: that is the hook Rails uses to let a later
  # condition on the same column replace an earlier one in +merge+ (how
  # association scopes are combined with default scopes), +rewhere+ and
  # +unscope(where:)+. Opting out means +other_tenant.projects+,
  # +Project.rewhere(account_id: x)+ and friends add their condition *alongside*
  # the tenant condition instead of replacing it — so they return nothing rather
  # than another tenant's rows.
  class TenantPredicate < Arel::Nodes::Equality
    def fetch_attribute(&)
      nil
    end
  end
end
