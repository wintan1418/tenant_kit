# Two tenants with a full data graph each, built with scoping disabled. Leak
# specs act as tenant A ("acme") and try to reach tenant B ("globex").
RSpec.shared_context "two tenants" do
  let!(:acme)   { Account.create!(name: "Acme", subdomain: "acme") }
  let!(:globex) { Account.create!(name: "Globex", subdomain: "globex") }

  let!(:graph) do
    TenantKit.without_tenant do
      [ acme, globex ].to_h do |account|
        project  = Project.create!(account: account, name: "#{account.name} project", slug: "site")
        task     = Task.create!(account: account, project: project, title: "#{account.name} task")
        user     = User.create!(email: "#{account.subdomain}@example.com")
        assign   = Assignment.create!(account: account, user: user, task: task)
        comment  = Comment.create!(account: account, commentable: project, body: "#{account.name} comment")
        contract = Contract.create!(account: account, title: "#{account.name} contract")
        invoice  = Invoice.create!(account: account, number: "INV-1")
        [ account.subdomain.to_sym,
          { project:, task:, user:, assignment: assign, comment:, contract:, invoice: } ]
      end
    end
  end

  let(:mine)   { graph[:acme] }
  let(:theirs) { graph[:globex] }

  def as_acme(&block)
    TenantKit.with_tenant(acme, &block)
  end

  def unscoped_count(model)
    TenantKit.without_tenant { model.count }
  end
end
