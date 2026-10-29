module Api
  class SessionsController < ApplicationController
    def create
      company = Company.find_by(slug: params[:company_slug])
      return render json: { error: "Company not found" }, status: :unauthorized unless company

      TenantConnection.switch(company.slug) do
        user = User.find_by(email: params[:email])

        if user&.authenticate(params[:password])
          token = JwtService.encode(sub: user.id, slug: company.slug)
          render json: { token: token }, status: :ok
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end
    end
  end
end
