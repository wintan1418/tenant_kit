module ApplicationCable
  class Channel < ActionCable::Channel::Base
    include TenantKit::Cable::Channel
  end
end
