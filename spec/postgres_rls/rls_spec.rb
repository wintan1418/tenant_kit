require "rails_helper"

# Runs only with DB=postgresql. Proves the database itself refuses
# cross-tenant access once RLS is enabled — including SQL that never goes
# through a TenantKit scope.
#
# Superusers bypass RLS, so each example switches to an ordinary role
# (tenant_kit_rls_app) after the fixtures are created.
RSpec.describe "PostgreSQL Row-Level Security", postgresql: true do
  app_role = "tenant_kit_rls_app"
  rls_tables = %w[projects tasks]

  before(:all) do
    TenantKit::PostgresRLS.install!
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL)
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{app_role}') THEN
          CREATE ROLE #{app_role} NOLOGIN NOSUPERUSER NOBYPASSRLS;
        END IF;
      END $$;
      GRANT USAGE ON SCHEMA public TO #{app_role};
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{app_role};
      GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{app_role};
    SQL
    rls_tables.each { |table| TenantKit::PostgresRLS.enable_sql(table).each { |sql| connection.execute(sql) } }
  end

  after(:all) do
    connection = ActiveRecord::Base.connection
    rls_tables.each { |table| TenantKit::PostgresRLS.disable_sql(table).each { |sql| connection.execute(sql) } }
  end

  around do |example|
    TenantKit.config.postgres_rls = true
    example.run
  ensure
    TenantKit.config.postgres_rls = false
    TenantKit.config.postgres_rls_strategy = :session
    TenantKit.config.postgres_rls_bypass = true
  end

  let(:connection) { ActiveRecord::Base.connection }

  def raw_names
    connection.select_values("SELECT name FROM projects ORDER BY name")
  end

  def tenant_setting
    connection.select_value("SELECT current_setting('tenant_kit.tenant_id', true)")
  end

  shared_context "rls fixtures" do
    let!(:acme)   { Account.create!(name: "Acme") }
    let!(:globex) { Account.create!(name: "Globex") }
    let!(:acme_project) { TenantKit.without_tenant { Project.create!(account: acme, name: "acme") } }
    let!(:globex_project) { TenantKit.without_tenant { Project.create!(account: globex, name: "globex") } }
  end

  context "inside a transaction (transactional examples)" do
    include_context "rls fixtures"

    # SET LOCAL: reverted when the example's transaction rolls back.
    before { connection.execute("SET LOCAL ROLE #{app_role}") }

    it "raw SQL sees only the current tenant's rows" do
      TenantKit.with_tenant(acme) { expect(raw_names).to eq([ "acme" ]) }
      TenantKit.with_tenant(globex) { expect(raw_names).to eq([ "globex" ]) }
    end

    it "find_by_sql, unscoped and select_all are filtered by the database" do
      TenantKit.with_tenant(acme) do
        expect(Project.find_by_sql("SELECT * FROM projects").map(&:name)).to eq([ "acme" ])
        expect(Project.unscoped.count).to eq(1)
        expect(connection.select_all("SELECT * FROM tasks").to_a).to be_empty
      end
    end

    it "with no tenant the database returns nothing (fail closed)" do
      expect(raw_names).to be_empty
      expect(tenant_setting).to eq("")
    end

    it "without_tenant sets the bypass setting and sees every row" do
      TenantKit.without_tenant { expect(raw_names).to eq(%w[acme globex]) }
    end

    it "without_tenant sees nothing when the bypass is disabled" do
      TenantKit.config.postgres_rls_bypass = false
      TenantKit.without_tenant { expect(raw_names).to be_empty }
    end

    it "refuses to insert a row for another tenant, even via raw SQL" do
      TenantKit.with_tenant(acme) do
        expect do
          connection.transaction(requires_new: true) do
            connection.execute("INSERT INTO projects (account_id, name, created_at, updated_at) " \
                               "VALUES (#{globex.id}, 'planted', now(), now())")
          end
        end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
    end

    it "refuses to update or delete another tenant's rows" do
      TenantKit.with_tenant(acme) do
        expect(Project.unscoped.where(id: globex_project.id).update_all(name: "pwned")).to eq(0)
        expect(Project.unscoped.where(id: globex_project.id).delete_all).to eq(0)
        globex_project.update_columns(name: "pwned")
      end
      TenantKit.without_tenant { expect(globex_project.reload.name).to eq("globex") }
    end

    it "refuses to move a row into another tenant via raw SQL" do
      TenantKit.with_tenant(acme) do
        expect do
          connection.transaction(requires_new: true) do
            connection.execute("UPDATE projects SET account_id = #{globex.id} WHERE id = #{acme_project.id}")
          end
        end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
      end
    end

    it "re-applies the tenant after a savepoint rollback reverts the setting" do
      TenantKit.with_tenant(acme) do
        expect(raw_names).to eq([ "acme" ])
        connection.transaction(requires_new: true) do
          TenantKit.with_tenant(globex) { expect(raw_names).to eq([ "globex" ]) }
          raise ActiveRecord::Rollback
        end
        expect(raw_names).to eq([ "acme" ])
        TenantKit.with_tenant(globex) { expect(raw_names).to eq([ "globex" ]) }
      end
    end

    it "a connection used by another thread is re-synced to that thread's tenant" do
      TenantKit.with_tenant(acme) do
        expect(raw_names).to eq([ "acme" ])
        other = Thread.new { TenantKit.with_tenant(globex) { raw_names } }.value
        expect(other).to eq([ "globex" ])
        expect(raw_names).to eq([ "acme" ])
      end
    end

    it "works with the :transaction strategy inside a transaction" do
      TenantKit.config.postgres_rls_strategy = :transaction
      TenantKit.with_tenant(acme) { expect(raw_names).to eq([ "acme" ]) }
      TenantKit.with_tenant(globex) { expect(raw_names).to eq([ "globex" ]) }
      expect(raw_names).to be_empty
    end

    it "TenantKit scoping still applies on top of RLS" do
      TenantKit.with_tenant(acme) do
        expect(Project.pluck(:name)).to eq([ "acme" ])
        expect(Project.create!(name: "new").account_id).to eq(acme.id)
      end
    end
  end

  context "outside a transaction (autocommit)" do
    self.use_transactional_tests = false

    include_context "rls fixtures"

    around do |example|
      connection.execute("SET ROLE #{app_role}")
      example.run
    ensure
      connection.execute("RESET ROLE")
      TenantKit.without_tenant do
        Project.unscoped.delete_all
        Account.delete_all
      end
    end

    it ":session strategy applies the tenant to autocommit statements" do
      TenantKit.with_tenant(acme) { expect(raw_names).to eq([ "acme" ]) }
      TenantKit.with_tenant(globex) { expect(raw_names).to eq([ "globex" ]) }
    end

    it ":transaction strategy fails closed outside a transaction and works inside one" do
      TenantKit.config.postgres_rls_strategy = :transaction
      TenantKit.with_tenant(acme) do
        expect(raw_names).to be_empty
        expect(connection.transaction { raw_names }).to eq([ "acme" ])
        expect(raw_names).to be_empty
      end
    end

    it "re-applies the tenant after a reconnect" do
      TenantKit.with_tenant(acme) do
        expect(raw_names).to eq([ "acme" ])
        connection.reconnect!
        connection.execute("SET ROLE #{app_role}")
        expect(raw_names).to eq([ "acme" ])
      end
    end
  end

  context "when config.postgres_rls is false" do
    it "does not touch the setting" do
      TenantKit.config.postgres_rls = false
      acme = Account.create!(name: "Acme")
      before = tenant_setting
      TenantKit.with_tenant(acme) { expect(tenant_setting).to eq(before) }
    end
  end
end
