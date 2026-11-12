require "rails_helper"
require "generators/tenant_kit/install/install_generator"
require "generators/tenant_kit/migration/migration_generator"
require "generators/tenant_kit/rls/rls_generator"

RSpec.describe "TenantKit generators" do
  let(:destination) { Rails.root.join("tmp/generator_specs") }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  end

  after { FileUtils.rm_rf(destination) }

  def run(klass, args = [])
    klass.start(args, destination_root: destination)
  end

  def read(relative)
    File.read(destination.join(relative))
  end

  describe "install" do
    it "writes the initializer with the configured tenant class" do
      run(TenantKit::Generators::InstallGenerator)
      body = read("config/initializers/tenant_kit.rb")
      expect(body).to include("TenantKit.configure")
      expect(body).to include('config.tenant_class = "Account"')
      expect(body).to include("config.require_tenant = true")
    end

    it "scaffolds the tenant model and its migration" do
      run(TenantKit::Generators::InstallGenerator)
      expect(read("app/models/account.rb")).to include("class Account < ApplicationRecord")
      migration = Dir[destination.join("db/migrate/*_create_accounts.rb")].first
      expect(migration).to be_present
      expect(File.read(migration)).to include("create_table :accounts")
    end

    it "skips the tenant model with --skip-tenant-model" do
      run(TenantKit::Generators::InstallGenerator, %w[--skip-tenant-model])
      expect(File.exist?(destination.join("app/models/account.rb"))).to be(false)
      expect(File.exist?(destination.join("config/initializers/tenant_kit.rb"))).to be(true)
    end
  end

  describe "migration" do
    it "generates a tenant reference migration for the given model" do
      run(TenantKit::Generators::MigrationGenerator, %w[Project])
      migration = Dir[destination.join("db/migrate/*_add_account_to_projects.rb")].first
      expect(migration).to be_present

      body = File.read(migration)
      expect(body).to include("class AddAccountToProjects")
      expect(body).to include("add_reference :projects, :account")
      expect(body).to include("null: false, foreign_key: true, index: true")
    end
  end

  describe "rls" do
    def rls_migration
      path = Dir[destination.join("db/migrate/*_enable_tenant_kit_rls*.rb")].first
      path && File.read(path)
    end

    it "writes an RLS migration for the named models" do
      run(TenantKit::Generators::RlsGenerator, %w[Project Invoice --column-type=bigint])
      body = rls_migration
      expect(body).to include("class EnableTenantKitRlsOnProjectsInvoices < ActiveRecord::Migration[")
      expect(body).to include('ALTER TABLE "projects" ENABLE ROW LEVEL SECURITY;')
      expect(body).to include('ALTER TABLE "invoices" FORCE ROW LEVEL SECURITY;')
      expect(body).to include("CREATE POLICY tenant_kit_isolation ON \"projects\"")
      expect(body).to include(%q("account_id" = NULLIF(current_setting('tenant_kit.tenant_id', true), '')::bigint))
      expect(body).to include("current_setting('tenant_kit.bypass', true) = 'on'")
      expect(body).to include('DROP POLICY IF EXISTS tenant_kit_isolation ON "invoices";')
    end

    it "omits the bypass clause with --no-bypass and honours --column-type" do
      run(TenantKit::Generators::RlsGenerator, %w[Project --no-bypass --column-type=uuid])
      body = rls_migration
      expect(body).not_to include("tenant_kit.bypass")
      expect(body).to include("::uuid")
    end

    it "discovers every tenant-owned base model when no models are given" do
      run(TenantKit::Generators::RlsGenerator)
      body = rls_migration
      expect(body).to include("class EnableTenantKitRls <")
      %w[projects invoices tasks assignments comments documents notes].each do |table|
        expect(body).to include(%(ALTER TABLE "#{table}" ENABLE ROW LEVEL SECURITY))
      end
      expect(body).not_to include('"accounts"')
      expect(body).not_to include('"users"')
    end

    it "reads the tenant column type from the database" do
      run(TenantKit::Generators::RlsGenerator, %w[Project])
      expect(rls_migration).to match(/::(bigint|integer)\b/)
    end

    it "skips names that are not tenant-owned models" do
      output = capture_stdout { run(TenantKit::Generators::RlsGenerator, %w[User]) }
      expect(output).to include("Skipping User")
      expect(rls_migration).to be_nil
    end

    it "the generated migration runs and rolls back" do
      skip "PostgreSQL only" unless ActiveRecord::Base.connection.adapter_name.match?(/postg/i)

      run(TenantKit::Generators::RlsGenerator, %w[Invoice --column-type=bigint])
      path = Dir[destination.join("db/migrate/*_enable_tenant_kit_rls*.rb")].first
      load path
      migration = EnableTenantKitRlsOnInvoices.new
      migration.verbose = false
      relrowsecurity = -> { ActiveRecord::Base.connection.select_value("SELECT relrowsecurity FROM pg_class WHERE relname = 'invoices'") }
      migration.migrate(:up)
      expect(relrowsecurity.call).to be(true)
      migration.migrate(:down)
      expect(relrowsecurity.call).to be(false)
    ensure
      Object.send(:remove_const, :EnableTenantKitRlsOnInvoices) if defined?(EnableTenantKitRlsOnInvoices)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
