require "rails_helper"

# Adversarial write paths: acting as tenant A, try to modify, delete, insert
# into, or move rows of tenant B.
RSpec.describe "Leak suite: writes" do
  include_context "two tenants"

  let(:their_project) { theirs[:project] }

  # MySQL upserts on any unique index and rejects :unique_by.
  let(:upsert_options) do
    ActiveRecord::Base.connection.supports_insert_conflict_target? ? { unique_by: %i[account_id slug] } : {}
  end

  def their_project_reloaded
    TenantKit.without_tenant { Project.find(their_project.id) }
  end

  describe "bulk relation writes" do
    it "update_all touches only the current tenant's rows" do
      as_acme { expect(Project.update_all(status: "pwned")).to eq(1) }
      expect(their_project_reloaded.status).to be_nil
    end

    it "update_all aimed at another tenant's id touches nothing" do
      as_acme { expect(Project.where(id: their_project.id).update_all(status: "pwned")).to eq(0) }
    end

    it "delete_all / destroy_all / delete_by / destroy_by spare other tenants" do
      as_acme do
        expect(Project.where(id: their_project.id).delete_all).to eq(0)
        expect(Project.destroy_by(id: their_project.id)).to be_empty
        expect(Project.delete_by(id: their_project.id)).to eq(0)
        Task.destroy_all
      end
      expect(unscoped_count(Project)).to eq(2)
      expect(unscoped_count(Task)).to eq(1)
    end

    it "touch_all touches only the current tenant's rows" do
      as_acme { expect(Project.touch_all).to eq(1) }
    end
  end

  describe "class-level writes by id" do
    it "Model.update(id) / Model.destroy(id) raise RecordNotFound for another tenant's id" do
      as_acme do
        expect { Project.update(their_project.id, name: "x") }.to raise_error(ActiveRecord::RecordNotFound)
        expect { Project.destroy(their_project.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "Model.delete(id) deletes nothing for another tenant's id" do
      as_acme { expect(Project.delete(their_project.id)).to eq(0) }
      expect(unscoped_count(Project)).to eq(2)
    end

    it "update_counters / increment_counter / decrement_counter cannot touch another tenant's row" do
      as_acme do
        expect(Project.update_counters(their_project.id, tasks_count: 5)).to eq(0)
        Project.increment_counter(:tasks_count, their_project.id)
        Project.decrement_counter(:tasks_count, their_project.id)
      end
      expect(their_project_reloaded.tasks_count).to eq(1)
    end

    it "update_counters still works for the current tenant" do
      as_acme { Project.update_counters(mine[:project].id, tasks_count: 2) }
      expect(TenantKit.without_tenant { mine[:project].reload.tasks_count }).to eq(3)
    end

    it "update_counters with no tenant raises in strict mode" do
      expect { Project.update_counters(their_project.id, tasks_count: 1) }.to raise_error(TenantKit::NoTenantSet)
    end
  end

  describe "counter_cache" do
    it "is maintained for the current tenant's parent" do
      as_acme { Task.create!(project: mine[:project], title: "another") }
      expect(TenantKit.without_tenant { mine[:project].reload.tasks_count }).to eq(2)
    end
  end

  describe "insert_all / upsert_all" do
    it "fills in the current tenant on rows that omit it" do
      as_acme { Project.insert_all([ { name: "bulk", slug: "bulk" } ]) }
      expect(TenantKit.without_tenant { Project.find_by!(slug: "bulk").account_id }).to eq(acme.id)
    end

    it "raises CrossTenantWrite for rows that name another tenant" do
      as_acme do
        expect { Project.insert_all([ { name: "bulk", account_id: globex.id } ]) }
          .to raise_error(TenantKit::CrossTenantWrite)
        expect { Project.upsert_all([ { name: "bulk", slug: "site", account_id: globex.id } ], **upsert_options) }
          .to raise_error(TenantKit::CrossTenantWrite)
        expect { Project.insert({ "name" => "bulk", "account_id" => globex.id }) }
          .to raise_error(TenantKit::CrossTenantWrite)
      end
      expect(unscoped_count(Project)).to eq(2)
    end

    it "accepts rows that name the current tenant" do
      as_acme { Project.insert_all!([ { name: "bulk", slug: "bulk", account_id: acme.id } ]) }
      expect(unscoped_count(Project)).to eq(3)
    end

    it "upsert_all cannot overwrite another tenant's row through a shared unique key" do
      as_acme do
        Project.upsert_all([ { name: "renamed", slug: "site" } ], **upsert_options)
      end
      expect(their_project_reloaded.name).to eq("Globex project")
      expect(TenantKit.without_tenant { mine[:project].reload.name }).to eq("renamed")
    end

    it "raises NoTenantSet with no tenant in strict mode" do
      expect { Project.insert_all([ { name: "bulk", account_id: globex.id } ]) }.to raise_error(TenantKit::NoTenantSet)
    end

    it "passes rows through unchanged inside without_tenant" do
      TenantKit.without_tenant { Project.insert_all([ { name: "seed", slug: "seed", account_id: globex.id } ]) }
      expect(unscoped_count(Project)).to eq(3)
    end
  end

  describe "creating and moving records across tenants" do
    it "a mass-assigned foreign tenant id is rejected on create" do
      as_acme do
        project = Project.new(name: "planted", account_id: globex.id)
        expect(project.save).to be(false)
        expect(project.errors[:account]).to include("must be the current tenant")
      end
    end

    it "changing the tenant of a persisted record is rejected" do
      as_acme do
        project = Project.find(mine[:project].id)
        expect(project.update(account_id: globex.id)).to be(false)
        expect(project.errors[:account]).to include("cannot be changed to another tenant")
        expect { project.update!(account: globex) }.to raise_error(ActiveRecord::RecordInvalid)
      end
      expect(TenantKit.without_tenant { mine[:project].reload.account_id }).to eq(acme.id)
    end

    it "moving a record between tenants is allowed inside without_tenant" do
      movable = TenantKit.without_tenant { Project.create!(account: acme, name: "movable") }
      TenantKit.without_tenant { movable.update!(account: globex) }
      expect(TenantKit.without_tenant { movable.reload.account_id }).to eq(globex.id)
    end

    it "update_column / update_columns skip validations (documented: caller responsibility)" do
      movable = TenantKit.without_tenant { Project.create!(account: acme, name: "movable") }
      as_acme { movable.update_column(:account_id, globex.id) }
      expect(TenantKit.without_tenant { movable.reload.account_id }).to eq(globex.id)
    end

    it "record-level writes on a record of another tenant are not filtered by default (documented)" do
      foreign = their_project_reloaded
      as_acme { foreign.update_columns(name: "pwned") }
      expect(their_project_reloaded.name).to eq("pwned")
    end
  end

  describe "config.scope_record_writes (opt-in)" do
    let(:guarded_model) do
      TenantKit.config.scope_record_writes = true
      Class.new(ApplicationRecord) do
        self.table_name = "projects"
        def self.name = "GuardedProject"
        belongs_to_tenant
      end
    ensure
      TenantKit.config.scope_record_writes = false
    end

    it "adds the tenant condition to record-level UPDATE and DELETE" do
      foreign = TenantKit.without_tenant { guarded_model.find(their_project.id) }
      as_acme do
        expect(foreign.update_columns(name: "pwned")).to be(false)
        foreign.destroy
      end
      expect(their_project_reloaded.name).to eq("Globex project")
      expect(unscoped_count(Project)).to eq(2)
    end

    it "still lets the owner tenant write its own records" do
      as_acme do
        record = guarded_model.find(mine[:project].id)
        expect(record.update_columns(name: "renamed")).to be(true)
      end
    end
  end

  describe "nested attributes" do
    it "children created through accepts_nested_attributes_for get the current tenant" do
      as_acme do
        project = Project.create!(name: "nested", tasks_attributes: [ { title: "child" } ])
        expect(project.tasks.first.account).to eq(acme)
      end
    end

    it "a child naming another tenant is rejected" do
      as_acme do
        project = Project.new(name: "nested", tasks_attributes: [ { title: "child", account_id: globex.id } ])
        expect(project.save).to be(false)
        expect(project.errors.attribute_names).to include(:"tasks.account")
      end
    end

    it "cannot update another tenant's child by id" do
      as_acme do
        project = Project.find(mine[:project].id)
        expect do
          project.update(tasks_attributes: [ { id: theirs[:task].id, title: "pwned" } ])
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
