require "net/http"

module Storage
  # Any S3-compatible service (AWS S3, MinIO, DigitalOcean Spaces, Linode),
  # spoken to with plain Net::HTTP and our own SigV4Signer: no S3 SDK.
  # Path-style URLs (endpoint/bucket/key) so it works without per-bucket DNS.
  #
  # Object keys are the SHA-256 of the blob id, not the id itself. Tested on
  # MinIO, raw ids broke: "..", "./a" and "a//b" were rejected, and "/leading"
  # silently overwrote "leading". Servers differ in these rules; hex never trips them.
  class S3Backend
    NETWORK_ERRORS = [ SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

    def initialize(endpoint:, bucket:, region:, access_key_id:, secret_access_key:)
      settings = { endpoint:, bucket:, region:, access_key_id:, secret_access_key: }
      missing = settings.select { |_, value| value.blank? }.keys
      raise ArgumentError, "S3 backend is missing settings: #{missing.join(", ")}" if missing.any?

      @endpoint = URI(endpoint)
      @bucket = bucket
      @signer = SigV4Signer.new(access_key_id:, secret_access_key:, region:)
    end

    def put(id, bytes)
      response = request(Net::HTTP::Put, id, bytes)
      raise Error, failure_message(response) unless response.is_a?(Net::HTTPSuccess)
    end

    def get(id)
      response = request(Net::HTTP::Get, id)
      return response.body.to_s.b if response.is_a?(Net::HTTPSuccess)
      # S3 also answers 404 for a missing bucket; only NoSuchKey means "no such blob".
      raise NotFound, "no S3 object for blob" if error_code(response) == "NoSuchKey"

      raise Error, failure_message(response)
    end

    private

    def request(request_class, id, body = nil)
      uri = object_uri(id)
      payload_sha256 = Digest::SHA256.hexdigest(body || "")
      headers = @signer.sign(method: request_class::METHOD, uri:, payload_sha256:,
                             headers: { "x-amz-content-sha256" => payload_sha256 })

      request = request_class.new(uri, headers)
      if body
        request.body = body
        request.content_type = "application/octet-stream" # unsigned; stops Net::HTTP's form-encoding default
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 30) do |http|
        http.request(request)
      end
    rescue *NETWORK_ERRORS => e
      raise Error, "S3 request failed: #{e.class}: #{e.message}"
    end

    def object_uri(id)
      key = Digest::SHA256.hexdigest(id)
      @endpoint.dup.tap { |uri| uri.path = "#{uri.path.chomp("/")}/#{SigV4Signer.uri_encode(@bucket)}/#{key}" }
    end

    # S3 errors are XML like <Error><Code>NoSuchBucket</Code>...</Error>.
    def error_code(response)
      response.body.to_s[%r{<Code>(.*?)</Code>}, 1]
    end

    def failure_message(response)
      "S3 responded #{response.code} #{error_code(response)}".strip
    end
  end
end
