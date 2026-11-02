class ApplicationController < ActionController::API
  before_action :authenticate!

  private

  # Bearer token auth (RFC 6750) against a single token from config.
  def authenticate!
    token = request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
    expected = Rails.configuration.x.api_token

    return if token && expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

    response.headers["WWW-Authenticate"] = 'Bearer realm="simple-drive"'
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
