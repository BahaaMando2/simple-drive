require "test_helper"

# Runs against a real S3-compatible server (MinIO in docker compose), because
# the point is to prove the hand-written signing is accepted by a real server.
class Storage::S3BackendTest < ActiveSupport::TestCase
  include StorageBackendContract

  setup { skip "S3_ENDPOINT not set; run via docker compose to test against MinIO" if settings[:endpoint].blank? }

  def settings
    Rails.configuration.x.storage[:s3]
  end

  def backend
    @backend ||= Storage::S3Backend.new(**settings)
  end

  test "a wrong secret key is rejected by the server" do
    impostor = Storage::S3Backend.new(**settings, secret_access_key: "not-the-real-secret")

    error = assert_raises(Storage::Error) { impostor.put("forged", "x") }
    assert_match(/403 SignatureDoesNotMatch/, error.message)
  end

  test "a missing bucket is reported, not mistaken for a missing blob" do
    other = Storage::S3Backend.new(**settings, bucket: "no-such-bucket")

    error = assert_raises(Storage::Error) { other.get("anything") }
    refute_kind_of Storage::NotFound, error
    assert_match(/NoSuchBucket/, error.message)
  end

  test "an unreachable endpoint becomes a Storage::Error" do
    offline = Storage::S3Backend.new(**settings, endpoint: "http://127.0.0.1:1")

    assert_raises(Storage::Error) { offline.get("anything") }
  end
end

class Storage::S3BackendConfigTest < ActiveSupport::TestCase
  test "refuses to start with missing settings" do
    error = assert_raises(ArgumentError) do
      Storage::S3Backend.new(endpoint: "http://s3", bucket: "", region: "us-east-1", access_key_id: nil, secret_access_key: "x")
    end
    assert_equal "S3 backend is missing settings: bucket, access_key_id", error.message
  end
end
