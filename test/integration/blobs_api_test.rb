require "test_helper"
require "minitest/mock"

class BlobsApiTest < ActionDispatch::IntegrationTest
  AUTH = { "Authorization" => "Bearer test-token" }.freeze
  HELLO = "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh" # "Hello Simple Storage World!", 27 bytes

  def post_blob(body)
    post "/v1/blobs", params: body, headers: AUTH, as: :json
  end

  def get_blob(path)
    get "/v1/blobs/#{path}", headers: AUTH
  end

  # --- the example from the brief ---

  test "stores and retrieves the brief's example exactly as specified" do
    post_blob(id: "any_valid_string_or_identifier", data: HELLO)
    assert_response :created

    get_blob("any_valid_string_or_identifier")
    assert_response :ok

    body = response.parsed_body
    assert_equal %w[id data size created_at], body.keys
    assert_equal "any_valid_string_or_identifier", body["id"]
    assert_equal HELLO, body["data"]
    assert_equal "27", body["size"] # decoded bytes, as a string like the brief
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, body["created_at"])
  end

  test "create returns metadata and the blob's location" do
    post_blob(id: "hello", data: HELLO)

    assert_equal %w[id size created_at], response.parsed_body.keys
    assert_equal "http://www.example.com/v1/blobs/hello", response.location
  end

  test "the Location URL works even for ids that URL normalization would mangle" do
    [ "a/b/", "/leading", "a//b", "docs/a b.txt", "100%", "a#b" ].each do |id|
      post_blob(id: id, data: HELLO)
      get response.location, headers: AUTH

      assert_response :ok, id
      assert_equal id, response.parsed_body["id"]
    end
  end

  test "binary data round-trips byte for byte" do
    data = Base64.strict_encode64((0..255).to_a.pack("C*"))
    post_blob(id: "binary", data: data)

    get_blob("binary")
    assert_equal data, response.parsed_body["data"]
    assert_equal "256", response.parsed_body["size"]
  end

  test "an empty blob is allowed" do
    post_blob(id: "empty", data: "")
    assert_response :created

    get_blob("empty")
    assert_equal({ "data" => "", "size" => "0" }, response.parsed_body.slice("data", "size"))
  end

  test "ids that look like paths round-trip through the URL" do
    id = "docs/2023/my report.pdf"
    post_blob(id: id, data: HELLO)

    get_blob("docs/2023/my%20report.pdf")
    assert_response :ok
    assert_equal id, response.parsed_body["id"]
  end

  # --- rejected input ---

  [
    [ "invalid characters", "not base64!!" ],
    [ "missing padding", "SGVsbG8" ],
    [ "line breaks (MIME style)", "SGVs\nbG8=" ],
    [ "URL-safe alphabet", "-_-_" ]
  ].each do |reason, data|
    test "rejects Base64 with #{reason}" do
      post_blob(id: "bad", data: data)

      assert_response :unprocessable_content
      assert_equal "data must be a valid Base64 string", response.parsed_body["error"]
      refute Blob.exists?("bad")
    end
  end

  test "rejects missing or non-string data" do
    [ { id: "x" }, { id: "x", data: 123 }, { id: "x", data: nil } ].each do |body|
      post_blob(body)
      assert_response :unprocessable_content, body.inspect
    end
  end

  test "rejects missing, non-string, blank or oversized ids" do
    [ { data: HELLO }, { id: 42, data: HELLO }, { id: "  ", data: HELLO }, { id: "x" * 1025, data: HELLO } ].each do |body|
      post_blob(body)
      assert_response :unprocessable_content, body.to_s[0, 60]
    end
  end

  test "an id containing a NUL character is rejected, not a server error" do
    post_blob(id: "a\u0000b", data: HELLO)
    assert_response :unprocessable_content
    assert_equal "Id must not contain NUL characters", response.parsed_body["error"]

    get_blob("a%00b")
    assert_response :not_found
  end

  test "rejects a malformed JSON body" do
    post "/v1/blobs", params: "{not json", headers: AUTH.merge("Content-Type" => "application/json")

    assert_response :bad_request
    assert_equal({ "error" => "request body is not valid JSON" }, response.parsed_body)
  end

  test "a duplicate id is rejected and the original data is kept" do
    post_blob(id: "taken", data: HELLO)
    post_blob(id: "taken", data: Base64.strict_encode64("overwrite attempt"))

    assert_response :conflict
    get_blob("taken")
    assert_equal HELLO, response.parsed_body["data"]
  end

  test "unknown id returns 404" do
    get_blob("nope")

    assert_response :not_found
    assert_equal({ "error" => "blob not found" }, response.parsed_body)
  end

  # --- backend failures ---

  test "a failed backend write returns 502 and leaves no metadata behind" do
    failing = Object.new
    def failing.put(*) = raise(Storage::Error, "disk on fire")

    Storage.stub(:backend, failing) { post_blob(id: "doomed", data: HELLO) }

    assert_response :bad_gateway
    refute Blob.exists?("doomed")
  end

  test "metadata whose bytes have gone missing returns 502, not a fake success" do
    Blob.create!(id: "orphan", size: 1, storage_backend: "local")

    get_blob("orphan")
    assert_response :bad_gateway
  end

  test "blob data is filtered out of the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal({ "id" => "x", "data" => "[FILTERED]" }, filter.filter("id" => "x", "data" => HELLO))
  end
end
