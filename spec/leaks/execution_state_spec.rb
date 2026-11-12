require "rails_helper"

# The current tenant lives in ActiveSupport::CurrentAttributes. These specs pin
# how it behaves across nesting, threads, fibers and the Rails executor.
RSpec.describe "Leak suite: execution state" do
  include_context "two tenants"

  describe "nesting" do
    it "with_tenant inside without_tenant is scoped (fixed in 0.2; 0.1 stayed unscoped)" do
      TenantKit.without_tenant do
        as_acme do
          expect(TenantKit.scoping_active?).to be(true)
          expect(Project.count).to eq(1)
        end
        expect(TenantKit.scoping_disabled?).to be(true)
        expect(Project.count).to eq(2)
      end
    end

    it "nested with_tenant restores the outer tenant, even on error" do
      as_acme do
        expect { TenantKit.with_tenant(globex) { raise "boom" } }.to raise_error("boom")
        expect(TenantKit::Current.tenant).to eq(acme)
        expect(Project.pluck(:name)).to eq([ "Acme project" ])
      end
    end

    it "with_tenant(nil) is not an escape hatch under strict mode" do
      as_acme do
        TenantKit.with_tenant(nil) { expect { Project.count }.to raise_error(TenantKit::NoTenantSet) }
      end
    end
  end

  describe "threads" do
    it "a new thread does not inherit the tenant, so strict mode raises there" do
      as_acme do
        outcome = Thread.new do
          [ TenantKit::Current.tenant, (Project.count rescue $!.class) ]
        end.value
        expect(outcome).to eq([ nil, TenantKit::NoTenantSet ])
      end
    end

    it "concurrent threads with different tenants do not see each other's tenant" do
      queue = Queue.new
      threads = [ acme, globex ].map do |tenant|
        Thread.new do
          TenantKit.with_tenant(tenant) do
            queue << :ready
            sleep 0.05
            TenantKit::Current.tenant.id
          end
        end
      end
      expect(threads.map(&:value)).to eq([ acme.id, globex.id ])
    end
  end

  describe "fibers" do
    it "fibers share the thread's tenant under the default :thread isolation level" do
      skip "isolation level is #{ActiveSupport::IsolatedExecutionState.isolation_level}" unless ActiveSupport::IsolatedExecutionState.isolation_level == :thread

      as_acme { expect(Fiber.new { TenantKit::Current.tenant }.resume).to eq(acme) }
    end

    it "fibers get their own tenant under :fiber isolation (e.g. Falcon)" do
      previous = ActiveSupport::IsolatedExecutionState.isolation_level
      ActiveSupport::IsolatedExecutionState.isolation_level = :fiber
      TenantKit::Current.tenant = acme
      expect(Fiber.new { TenantKit::Current.tenant }.resume).to be_nil
    ensure
      TenantKit::Current.reset
      ActiveSupport::IsolatedExecutionState.isolation_level = previous
    end
  end

  describe "Rails executor" do
    it "resets the tenant when a unit of work (request, job) completes" do
      outcome = Thread.new do
        Rails.application.executor.wrap { TenantKit::Current.tenant = acme }
        TenantKit::Current.tenant
      end.value
      expect(outcome).to be_nil
    end

    it "starts each unit of work without a tenant" do
      outcome = Thread.new do
        TenantKit::Current.tenant = acme
        Rails.application.executor.wrap { TenantKit::Current.tenant }
      end.value
      expect(outcome).to be_nil
    end
  end
end
