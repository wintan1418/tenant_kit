require "rails_helper"

RSpec.describe "Controller tenant resolution", type: :request do
  let!(:acme) do
    TenantKit.without_tenant do
      Account.create!(name: "Acme", subdomain: "acme", domain: "acme.test")
    end
  end
  let!(:globex) do
    TenantKit.without_tenant do
      Account.create!(name: "Globex", subdomain: "globex", domain: "globex.test")
    end
  end

  describe "by subdomain" do
    it "sets the tenant from request.subdomain" do
      get "/by_subdomain", headers: { "Host" => "acme.example.com" }
      expect(response.body).to eq("Acme")
    end

    it "resolves a different subdomain to a different tenant" do
      get "/by_subdomain", headers: { "Host" => "globex.example.com" }
      expect(response.body).to eq("Globex")
    end

    it "resets the tenant after the request" do
      get "/by_subdomain", headers: { "Host" => "acme.example.com" }
      expect(TenantKit::Current.tenant).to be_nil
    end
  end

  describe "by domain" do
    it "sets the tenant from request.host" do
      get "/by_domain", headers: { "Host" => "acme.test" }
      expect(response.body).to eq("Acme")
    end
  end

  describe "by header" do
    it "sets the tenant from the configured header" do
      get "/by_header", headers: { "X-Tenant-Id" => globex.id.to_s }
      expect(response.body).to eq("Globex")
    end

    it "leaves the tenant unset when the header is absent" do
      get "/by_header"
      expect(response.body).to eq("")
    end
  end
end
