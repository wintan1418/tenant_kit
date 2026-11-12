module TenantKit
  # Opt-in explicit scoping: +belongs_to_tenant scoping: :explicit+.
  #
  # The model gets no tenant +default_scope+. Instead, callers scope at the call
  # site with +Model.for_current_tenant+. Because explicit scoping fails *open*
  # when someone forgets, TenantKit installs a guard: a query against the model
  # that neither went through +for_current_tenant+ nor carries an equality
  # condition on the tenant column is reported — it raises
  # {ExplicitScopeMissing} in development and test, and is logged (and
  # instrumented as +explicit_scope_missing.tenant_kit+) elsewhere. Configure
  # with {Configuration#explicit_scoping_guard}.
  #
  # Exempt from the guard: queries inside {TenantKit.without_tenant}, and
  # association reads from an already-loaded record (+account.notes+,
  # +comment.note+), which Rails builds as an +AssociationRelation+. Preloading
  # (+includes+ / +preload+ / +eager_load+) is checked like any other query; give
  # the association a scope (+has_many :notes, -> { for_current_tenant }+) to
  # make it explicit.
  #
  # Everything else TenantKit does for owned models — auto-assignment,
  # presence validation, cross-tenant write validation, the +insert_all+ /
  # +update_counters+ guards — applies in explicit mode too.
  module ExplicitScoping
    # Marker extended onto relations built by +for_current_tenant+.
    module Scoped; end

    # Extended onto every relation of an explicit-mode model (via its
    # +default_scope+) while the guard is enabled. Checks the relation right
    # before it touches the database.
    module Guard
      def calculate(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def pluck(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def ids(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def exists?(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def update_all(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def delete_all(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      private

      def exec_queries(...)
        _tenant_kit_check_explicit_scope!
        super
      end

      def _tenant_kit_check_explicit_scope!
        return if TenantKit.scoping_disabled?
        return if extending_values.include?(TenantKit::ExplicitScoping::Scoped)
        return if is_a?(ActiveRecord::AssociationRelation)
        return if where_values_hash.key?(klass._tenant_kit_foreign_key)

        TenantKit::ExplicitScoping.report(klass)
      end
    end

    class << self
      # Installs the +for_current_tenant+ scope and the guard on +model+.
      #
      # @api private
      def install(model)
        model.scope :for_current_tenant, lambda {
          relation =
            if TenantKit.scoping_active?
              where(klass._tenant_kit_predicate(TenantKit.current_tenant_id))
            elsif TenantKit.scoping_disabled?
              all
            elsif TenantKit.config.require_tenant
              raise TenantKit::NoTenantSet, "No current tenant set for #{klass.name}"
            else
              none
            end
          relation.extending(TenantKit::ExplicitScoping::Scoped)
        }

        model.send(:default_scope) do
          TenantKit.config.explicit_scoping_guard ? all.extending(TenantKit::ExplicitScoping::Guard) : all
        end
      end

      # Reports a query that skipped explicit scoping, per the configured guard.
      #
      # @api private
      def report(model)
        message = "#{model.name} is declared with belongs_to_tenant scoping: :explicit " \
                  "but was queried without #{model.name}.for_current_tenant " \
                  "(or a condition on #{model._tenant_kit_foreign_key})"

        ActiveSupport::Notifications.instrument("explicit_scope_missing.tenant_kit", model: model.name)

        case TenantKit.config.explicit_scoping_guard
        when :raise
          raise TenantKit::ExplicitScopeMissing, message
        when :log
          (defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger)&.warn("[TenantKit] #{message}")
        end
      end
    end
  end
end
