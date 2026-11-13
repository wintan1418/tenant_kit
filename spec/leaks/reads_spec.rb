require "rails_helper"

# Adversarial read paths: acting as tenant A, try to read tenant B's rows.
RSpec.describe "Leak suite: reads" do
  include_context "two tenants"

  let(:their_id) { theirs[:project].id }

  describe "finder and query methods with another tenant's id" do
    it "find raises RecordNotFound" do
      as_acme { expect { Project.find(their_id) }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    it "find with several ids raises RecordNotFound" do
      as_acme { expect { Project.find([ mine[:project].id, their_id ]) }.to raise_error(ActiveRecord::RecordNotFound) }
    end

    it "find_by / find_by! / find_sole_by return nothing" do
      as_acme do
        expect(Project.find_by(id: their_id)).to be_nil
        expect { Project.find_by!(id: their_id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect { Project.find_sole_by(id: their_id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "where / exists? / pluck / ids / pick return nothing" do
      as_acme do
        expect(Project.where(id: their_id).to_a).to be_empty
        expect(Project.exists?(their_id)).to be(false)
        expect(Project.where(id: their_id).exists?).to be(false)
        expect(Project.where(id: their_id).pluck(:name)).to be_empty
        expect(Project.ids).to eq([ mine[:project].id ])
        expect(Project.where(id: their_id).pick(:name)).to be_nil
      end
    end

    it "count / sum / maximum / group counts see only the current tenant" do
      as_acme do
        expect(Project.count).to eq(1)
        expect(Project.sum(:tasks_count)).to eq(Project.where(account_id: acme.id).sum(:tasks_count))
        expect(Project.maximum(:id)).to eq(mine[:project].id)
        expect(Project.group(:account_id).count).to eq({ acme.id => 1 })
      end
    end

    it "first / last / take / find_each / in_batches see only the current tenant" do
      as_acme do
        expect([ Project.first, Project.last, Project.take ]).to all(eq(mine[:project]))
        expect(Project.find_each.to_a).to eq([ mine[:project] ])
        expect(Project.in_batches.flat_map(&:to_a)).to eq([ mine[:project] ])
      end
    end

    it "explicitly naming another tenant's id in a condition returns nothing" do
      as_acme do
        expect(Project.where(account_id: globex.id).to_a).to be_empty
        expect(Project.where(account: globex).to_a).to be_empty
        expect(Project.where("account_id = ?", globex.id).to_a).to be_empty
      end
    end

    it "or-ed conditions keep the tenant condition on both sides" do
      as_acme do
        relation = Project.where(id: mine[:project].id).or(Project.where(id: their_id))
        expect(relation.to_a).to eq([ mine[:project] ])
      end
    end
  end

  describe "replacing the tenant condition" do
    it "rewhere on the tenant column cannot replace it" do
      as_acme { expect(Project.rewhere(account_id: globex.id).to_a).to be_empty }
    end

    it "unscope(where: tenant_column) cannot remove it" do
      as_acme { expect(Project.unscope(where: :account_id).to_a).to eq([ mine[:project] ]) }
    end

    it "merge with a relation on the tenant column cannot replace it" do
      as_acme do
        other = Project.unscoped.where(account_id: globex.id)
        expect(Project.all.merge(other).to_a).to be_empty
      end
    end
  end

  describe "unscoped vs without_tenant" do
    it "unscoped drops the tenant condition (documented: never use it on owned models)" do
      as_acme { expect(Project.unscoped.count).to eq(2) }
    end

    it "unscoped with a block drops it for everything in the block" do
      as_acme { expect(Project.unscoped { Project.count }).to eq(2) }
    end

    it "without_tenant lifts only the tenant condition and is the sanctioned escape" do
      as_acme do
        TenantKit.without_tenant do
          expect(Project.count).to eq(2)
          expect(Project.where(slug: "site").count).to eq(2)
        end
        expect(Project.count).to eq(1)
      end
    end

    it "without_tenant restores scoping even when the block raises" do
      as_acme do
        expect { TenantKit.without_tenant { raise "boom" } }.to raise_error("boom")
        expect(Project.count).to eq(1)
      end
    end
  end

  describe "raw SQL (caller responsibility unless Postgres RLS is enabled)" do
    it "find_by_sql is not scoped" do
      as_acme { expect(Project.find_by_sql("SELECT * FROM projects").size).to eq(2) }
    end

    it "connection.select_all is not scoped" do
      as_acme do
        rows = ActiveRecord::Base.connection.select_all("SELECT id FROM projects").to_a
        expect(rows.size).to eq(2)
      end
    end

    it "find_by_sql through a scoped relation's SQL is scoped" do
      as_acme { expect(Project.find_by_sql(Project.all.to_sql).map(&:id)).to eq([ mine[:project].id ]) }
    end
  end

  describe "strict mode with no tenant" do
    it "raises NoTenantSet for every read path" do
      [
        -> { Project.find(their_id) },
        -> { Project.find_by(id: their_id) },
        -> { Project.where(id: their_id).to_a },
        -> { Project.exists?(their_id) },
        -> { Project.pluck(:id) },
        -> { Project.count },
        -> { Project.first }
      ].each { |read| expect(&read).to raise_error(TenantKit::NoTenantSet) }
    end
  end
end
