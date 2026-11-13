# Renders tenant-scoped data, so a mailer delivered later must run under the
# tenant that enqueued it.
class ProjectMailer < ApplicationMailer
  default from: "app@example.com"

  def summary(project = nil)
    @project = project
    @names = Project.order(:id).pluck(:name)
    mail(to: "owner@example.com", subject: "Projects for #{TenantKit::Current.tenant&.name}")
  end
end
