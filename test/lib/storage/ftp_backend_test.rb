require "test_helper"

# Runs against a real FTP server (vsftpd in docker compose and CI).
class Storage::FtpBackendTest < ActiveSupport::TestCase
  include StorageBackendContract

  setup { skip "FTP_HOST not set; run via docker compose to test against the FTP server" if settings[:host].blank? }

  def settings
    Rails.configuration.x.storage[:ftp]
  end

  def backend
    @backend ||= Storage::FtpBackend.new(**settings)
  end

  test "a wrong password is a backend error, not a missing blob" do
    intruder = Storage::FtpBackend.new(**settings, password: "wrong")

    error = assert_raises(Storage::Error) { intruder.get("anything") }
    refute_kind_of Storage::NotFound, error
  end

  test "an unreachable server becomes a Storage::Error" do
    offline = Storage::FtpBackend.new(**settings, host: "127.0.0.1", port: 1)

    assert_raises(Storage::Error) { offline.get("anything") }
  end
end

class Storage::FtpBackendConfigTest < ActiveSupport::TestCase
  test "refuses to start with missing settings" do
    error = assert_raises(ArgumentError) { Storage::FtpBackend.new(host: "ftp", user: "", password: nil) }

    assert_equal "FTP backend is missing settings: user, password", error.message
  end
end
