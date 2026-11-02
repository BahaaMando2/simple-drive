require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "rejects a request without a token" do
    get "/v1/blobs/anything"

    assert_response :unauthorized
    assert_equal 'Bearer realm="simple-drive"', response.headers["WWW-Authenticate"]
    assert_equal({ "error" => "unauthorized" }, response.parsed_body)
  end

  test "rejects a wrong token" do
    get "/v1/blobs/anything", headers: { "Authorization" => "Bearer wrong" }

    assert_response :unauthorized
  end

  test "rejects the right token under a non-Bearer scheme" do
    get "/v1/blobs/anything", headers: { "Authorization" => "Basic test-token" }

    assert_response :unauthorized
  end

  test "rejects everything when no token is configured" do
    with_api_token(nil) do
      get "/v1/blobs/anything", headers: { "Authorization" => "Bearer " }

      assert_response :unauthorized
    end
  end

  test "accepts the configured token, scheme case-insensitive" do
    get "/v1/blobs/anything", headers: { "Authorization" => "bearer test-token" }

    assert_response :not_found # authenticated; the blob just doesn't exist
  end

  test "health check needs no token" do
    get "/up"

    assert_response :success
  end

  private

  def with_api_token(value)
    original = Rails.configuration.x.api_token
    Rails.configuration.x.api_token = value
    yield
  ensure
    Rails.configuration.x.api_token = original
  end
end
