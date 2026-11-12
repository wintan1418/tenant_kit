require "rails_helper"

# Active Storage's own tables (blobs, attachments) are global. Reaching an
# attachment through a tenant-owned record is scoped by that record; querying
# ActiveStorage::Attachment / Blob directly is not.
RSpec.describe "Leak suite: Active Storage" do
  include_context "two tenants"

  before do
    TenantKit.without_tenant do
      [ mine[:project], theirs[:project] ].each do |project|
        project.brief.attach(io: StringIO.new("brief for #{project.name}"), filename: "brief.txt", content_type: "text/plain")
      end
    end
  end

  it "attachments reached through the owner are scoped by the owner" do
    as_acme do
      expect(Project.find(mine[:project].id).brief.download).to eq("brief for Acme project")
      expect(Project.find_by(id: theirs[:project].id)).to be_nil
    end
  end

  it "with_attached_* preloading is scoped" do
    as_acme { expect(Project.with_attached_brief.map { |p| p.brief.filename.to_s }).to eq([ "brief.txt" ]) }
  end

  it "attaching under a tenant works" do
    as_acme do
      project = Project.create!(name: "with file")
      project.brief.attach(io: StringIO.new("x"), filename: "x.txt")
      expect(project.reload.brief).to be_attached
    end
  end

  it "ActiveStorage::Attachment and Blob are global (documented: caller responsibility)" do
    as_acme do
      expect(ActiveStorage::Attachment.where(record_type: "Project").count).to eq(2)
      expect(ActiveStorage::Blob.count).to eq(2)
    end
  end

  it "a blob's signed id resolves regardless of tenant (documented: caller responsibility)" do
    signed = TenantKit.without_tenant { theirs[:project].brief.blob.signed_id }
    as_acme { expect(ActiveStorage::Blob.find_signed(signed)).to be_present }
  end
end
