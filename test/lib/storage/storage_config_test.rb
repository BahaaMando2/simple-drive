require "test_helper"

class StorageConfigTest < ActiveSupport::TestCase
  test "secrets containing YAML syntax survive config/storage.yml intact" do
    with_env("FTP_PASSWORD" => "p#ss: word", "S3_SECRET_ACCESS_KEY" => "wJal/K7+MDENG") do
      config = Rails.application.config_for(:storage)

      assert_equal "p#ss: word", config[:ftp][:password]
      assert_equal "wJal/K7+MDENG", config[:s3][:secret_access_key]
    end
  end

  test "an unknown backend name is refused" do
    error = assert_raises(ArgumentError) { Storage.backend("dropbox") }

    assert_match(/Unknown storage backend "dropbox"/, error.message)
  end

  private

  def with_env(vars)
    original = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
