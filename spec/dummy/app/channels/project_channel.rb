# Streams one project's updates on a tenant-prefixed stream.
class ProjectChannel < ApplicationCable::Channel
  def subscribed
    project = TenantKit.without_tenant { Project.find_by(id: params[:id]) }
    return reject unless project

    stream_for_tenant project
  end
end
