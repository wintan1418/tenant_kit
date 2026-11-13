# Turbo Streams channel that refuses signed stream names of other tenants.
class TenantStreamsChannel < Turbo::StreamsChannel
  include TenantKit::Turbo::StreamsChannel
end
