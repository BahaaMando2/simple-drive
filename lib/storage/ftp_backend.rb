require "net/ftp"
require "digest"

module Storage
  # Stores each blob as one file on an FTP server, named by the SHA-256 of its
  # id (same reasoning as the local and S3 backends: ids are never paths).
  # One short connection per operation: FTP sessions are stateful and servers
  # drop idle ones, so a shared long-lived connection would need reconnect logic.
  class FtpBackend
    NETWORK_ERRORS = [ Net::FTPError, SocketError, SystemCallError, IOError, Timeout::Error ].freeze

    def initialize(host:, user:, password:, port: 21)
      settings = { host:, user:, password: }
      missing = settings.select { |_, value| value.blank? }.keys
      raise ConfigurationError, "FTP backend is missing settings: #{missing.join(", ")}" if missing.any?

      @host = host
      @port = Integer(port)
      @user = user
      @password = password
    end

    def put(id, bytes)
      session { |ftp| ftp.storbinary("STOR #{filename(id)}", StringIO.new(bytes), Net::FTP::DEFAULT_BLOCKSIZE) }
    end

    def get(id)
      bytes = +"".b
      session { |ftp| ftp.retrbinary("RETR #{filename(id)}", Net::FTP::DEFAULT_BLOCKSIZE) { |chunk| bytes << chunk } }
      bytes
    end

    private

    def session(&block)
      Net::FTP.open(@host, port: @port, username: @user, password: @password,
                           passive: true, open_timeout: 5, read_timeout: 30, &block)
    rescue Net::FTPPermError => e
      # 550 = "requested action not taken: file unavailable"
      raise NotFound, "no FTP file for blob" if e.message.start_with?("550")

      raise Error, "FTP request failed: #{e.message.strip}"
    rescue *NETWORK_ERRORS => e
      raise Error, "FTP request failed: #{e.class}: #{e.message.strip}"
    end

    def filename(id)
      Digest::SHA256.hexdigest(id)
    end
  end
end
