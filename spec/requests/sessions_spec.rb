require "rails_helper"

RSpec.describe "POST /api/login", type: :request do
  let!(:company) { Company.find_or_create_by!(slug: "acme") { |c| c.name = "Acme Corp" } }

  before do
    TenantConnection.switch("acme") do
      User.find_or_create_by!(email: "admin@acme.com") do |u|
        u.password              = "password123"
        u.password_confirmation = "password123"
      end
    end
  end

  describe "valid credentials" do
    it "returns 200 and a JWT token" do
      post "/api/login", params: {
        company_slug: "acme",
        email:        "admin@acme.com",
        password:     "password123"
      }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["token"]).to be_present
    end

    it "JWT contains correct claims" do
      post "/api/login", params: {
        company_slug: "acme",
        email:        "admin@acme.com",
        password:     "password123"
      }

      token = JSON.parse(response.body)["token"]
      payload = JwtService.decode(token)

      TenantConnection.switch("acme") do
        user = User.find_by!(email: "admin@acme.com")
        expect(payload["sub"]).to eq(user.id)
      end

      expect(payload["slug"]).to eq("acme")
      expect(payload["exp"]).to be > Time.current.to_i
    end
  end

  describe "wrong password" do
    it "returns 401" do
      post "/api/login", params: {
        company_slug: "acme",
        email:        "admin@acme.com",
        password:     "wrongpassword"
      }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "unknown company slug" do
    it "returns 401" do
      post "/api/login", params: {
        company_slug: "unknown-slug",
        email:        "admin@acme.com",
        password:     "password123"
      }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
