module JwtService
  ALGORITHM = "HS256".freeze
  EXPIRY = 24.hours

  def self.secret
    Rails.application.secret_key_base
  end

  def self.encode(payload)
    payload = payload.merge(exp: EXPIRY.from_now.to_i)
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, secret, true, algorithm: ALGORITHM)
    HashWithIndifferentAccess.new(decoded.first)
  rescue JWT::DecodeError => e
    raise JWT::DecodeError, e.message
  end
end
