module Api
  class BaseController < ApplicationController
    before_action :authenticate!

    private

    def authenticate!
      token = request.headers["Authorization"]&.split(" ", 2)&.last
      return render_unauthorized unless token

      payload = JwtService.decode(token)
      Current.user = User.find_by(id: payload["sub"])
      Current.company_slug = payload["slug"]

      render_unauthorized unless Current.user
    rescue JWT::DecodeError
      render_unauthorized
    end

    def render_unauthorized(message = "Unauthorized")
      render json: { error: message }, status: :unauthorized
    end
  end
end
