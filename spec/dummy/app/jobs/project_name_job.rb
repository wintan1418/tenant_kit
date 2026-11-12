# Takes a tenant-owned record as an argument (serialized as a GlobalID).
class ProjectNameJob < ApplicationJob
  RESULTS = []

  def perform(project, extra = {})
    RESULTS << [ TenantKit::Current.tenant&.id, project.name, Project.count ]
  end
end
