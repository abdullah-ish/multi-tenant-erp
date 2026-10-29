class TenantMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if TenantConnection::PUBLIC_PATHS.include?(request.path)
      return @app.call(env)
    end

    token = extract_token(env)
    unless token
      return [401, { "Content-Type" => "application/json" }, ['{"error":"Missing token"}']]
    end

    begin
      payload = JwtService.decode(token)
      slug    = payload["slug"]

      raise JWT::DecodeError, "Missing slug" if slug.blank?

      Current.company_slug = slug
      TenantConnection.switch(slug) { @app.call(env) }
    rescue JWT::DecodeError => e
      [401, { "Content-Type" => "application/json" }, [{ error: e.message }.to_json]]
    end
  end

  private

  def extract_token(env)
    auth_header = env["HTTP_AUTHORIZATION"]
    return nil unless auth_header&.start_with?("Bearer ")
    auth_header.split(" ", 2).last
  end
end
