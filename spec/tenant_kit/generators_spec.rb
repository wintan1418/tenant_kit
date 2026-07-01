require "rails_helper"
require "generators/tenant_kit/install/install_generator"
require "generators/tenant_kit/migration/migration_generator"

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
end
