class ApplicationController < ActionController::API
  # The wrapper copies the JSON body under a "blob" key we never read, and it parses
  # the body before rescue_from is active, so a malformed body escaped our handler.
  wrap_parameters false

  before_action :authenticate!

  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render_error "request body is not valid JSON", :bad_request
  end

  private

  # Bearer token auth (RFC 6750) against a single token from config.
  def authenticate!
    token = request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
    expected = Rails.configuration.x.api_token

    return if token && expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

    response.headers["WWW-Authenticate"] = 'Bearer realm="simple-drive"'
    render_error "unauthorized", :unauthorized
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
