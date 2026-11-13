require "rails_helper"

# Adversarial association paths: joins, preloading, through associations,
# polymorphic and STI models, and associations reached from global records.
RSpec.describe "Leak suite: associations" do
  include_context "two tenants"

  describe "has_many from the (global) tenant model" do
    it "another tenant's has_many is empty under the current tenant" do
      as_acme do
        expect(globex.projects.to_a).to be_empty
        expect(globex.projects.count).to eq(0)
        expect(Account.find(globex.id).invoices.to_a).to be_empty
      end
    end

    it "the current tenant's has_many works" do
      as_acme { expect(acme.projects.to_a).to eq([ mine[:project] ]) }
    end

    it "another tenant's has_many works inside without_tenant" do
      TenantKit.without_tenant { expect(globex.projects.to_a).to eq([ theirs[:project] ]) }
    end
  end

  describe "joins / includes / preload / eager_load" do
    it "joins applies the tenant condition to the joined table" do
      as_acme do
        expect(Account.joins(:projects).distinct.pluck(:id)).to eq([ acme.id ])
        expect(Account.where(id: globex.id).joins(:projects).count).to eq(0)
      end
    end

    it "includes / preload / eager_load load only the current tenant's children" do
      as_acme do
        %i[includes preload eager_load].each do |loader|
          accounts = Account.where(id: [ acme.id, globex.id ]).order(:id).public_send(loader, :projects).to_a
          expect(accounts.map { |a| a.projects.map(&:id) }).to eq([ [ mine[:project].id ], [] ]), loader.to_s
        end
      end
    end

    it "left_outer_joins applies the tenant condition" do
      as_acme do
        counts = Account.left_outer_joins(:projects).group("accounts.id").count("projects.id")
        expect(counts).to eq({ acme.id => 1, globex.id => 0 })
      end
    end
  end

  describe "has_many :through" do
    it "through a tenant-owned join model is scoped on both tables" do
      as_acme do
        expect(globex.tasks.to_a).to be_empty
        expect(acme.tasks.to_a).to eq([ mine[:task] ])
      end
    end

    it "from a global model through tenant-owned rows is scoped" do
      as_acme do
        expect(theirs[:user].tasks.to_a).to be_empty
        expect(mine[:user].tasks.to_a).to eq([ mine[:task] ])
      end
    end

    it "nested through is scoped" do
      as_acme { expect(Project.find(mine[:project].id).assignments.to_a).to eq([ mine[:assignment] ]) }
    end
  end

  describe "belongs_to pointing at another tenant's row" do
    it "loads nil instead of the other tenant's record" do
      foreign = TenantKit.without_tenant { Task.create!(account: acme, project: theirs[:project], title: "dangling") }
      as_acme { expect(Task.find(foreign.id).project).to be_nil }
    end

    it "a required belongs_to cannot be created pointing at another tenant's row" do
      as_acme do
        task = Task.new(project_id: theirs[:project].id, title: "smuggled")
        expect(task).not_to be_valid
        expect(task.errors[:project]).to be_present
      end
    end
  end

  describe "polymorphic belongs_to" do
    it "a polymorphic target in another tenant loads nil" do
      foreign = TenantKit.without_tenant do
        Comment.create!(account: acme, commentable: theirs[:project], body: "x")
      end
      as_acme { expect(Comment.find(foreign.id).commentable).to be_nil }
    end

    it "cannot be created pointing at another tenant's row" do
      as_acme do
        comment = Comment.new(commentable_type: "Project", commentable_id: theirs[:project].id, body: "x")
        expect(comment).not_to be_valid
        expect(comment.errors[:commentable]).to be_present
      end
    end

    it "has_many as: is scoped" do
      as_acme { expect(Project.find(mine[:project].id).comments.to_a).to eq([ mine[:comment] ]) }
    end
  end

  describe "STI" do
    it "subclasses inherit the tenant scope" do
      as_acme do
        expect(Contract.count).to eq(1)
        expect(Document.count).to eq(1)
        expect(Contract.find_by(id: theirs[:contract].id)).to be_nil
      end
    end

    it "subclasses raise NoTenantSet with no tenant" do
      expect { Contract.count }.to raise_error(TenantKit::NoTenantSet)
    end

    it "subclasses auto-assign and validate the tenant" do
      as_acme { expect(Proposal.create!(title: "p").account).to eq(acme) }
    end
  end
end
