require "openssl"
require "digest"

module Storage
  # AWS Signature Version 4, implemented from the spec:
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
  #
  # The secret key never leaves this process. Instead the request (method, path,
  # chosen headers, body hash, time) is signed with a key derived from it, and
  # the server recomputes the signature to verify both who sent the request and
  # that nothing in it was changed.
  class SigV4Signer
    ALGORITHM = "AWS4-HMAC-SHA256".freeze

    # RFC 3986 percent-encoding as SigV4 requires: every byte except A-Z a-z
    # 0-9 - . _ ~ becomes %XX (uppercase hex). Object keys keep their "/".
    def self.uri_encode(string, encode_slash: true)
      unreserved = encode_slash ? /[^A-Za-z0-9\-._~]/n : %r{[^A-Za-z0-9\-._~/]}n
      string.b.gsub(unreserved) { |byte| format("%%%02X", byte.ord) }
    end

    def initialize(access_key_id:, secret_access_key:, region:, service: "s3")
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @region = region
      @service = service
    end

    # Returns the headers to send: the given ones plus host, x-amz-date and
    # authorization. uri.path must already be encoded with .uri_encode; S3 uses
    # it as-is (unlike other AWS services, S3 does not encode it twice).
    def sign(method:, uri:, payload_sha256:, headers: {}, time: Time.now)
      amz_date = time.utc.strftime("%Y%m%dT%H%M%SZ")
      headers = headers.transform_keys(&:downcase).merge("host" => host(uri), "x-amz-date" => amz_date)

      request = canonical_request(method, uri, headers, payload_sha256)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key(amz_date[0, 8]), string_to_sign(amz_date, request))

      headers.merge(
        "authorization" => "#{ALGORITHM} Credential=#{@access_key_id}/#{scope(amz_date[0, 8])}, " \
                           "SignedHeaders=#{signed_headers(headers)}, Signature=#{signature}"
      )
    end

    # Step 1: the request in one exact text form that both sides can rebuild.
    def canonical_request(method, uri, headers, payload_sha256)
      [
        method,
        uri.path.empty? ? "/" : uri.path,
        "", # canonical query string: our requests never have one
        headers.sort.map { |name, value| "#{name}:#{value.to_s.strip.squeeze(" ")}\n" }.join,
        signed_headers(headers),
        payload_sha256
      ].join("\n")
    end

    # Step 2: what actually gets signed: algorithm, time, scope, request hash.
    def string_to_sign(amz_date, canonical_request)
      [ ALGORITHM, amz_date, scope(amz_date[0, 8]), Digest::SHA256.hexdigest(canonical_request) ].join("\n")
    end

    private

    # Step 3: a key valid only for this day, region and service, derived from
    # the secret in four HMAC rounds. Step 4 (the signature) happens in #sign.
    def signing_key(date)
      [ date, @region, @service, "aws4_request" ].inject("AWS4#{@secret_access_key}") do |key, part|
        OpenSSL::HMAC.digest("SHA256", key, part)
      end
    end

    def scope(date)
      "#{date}/#{@region}/#{@service}/aws4_request"
    end

    def signed_headers(headers)
      headers.keys.sort.join(";")
    end

    def host(uri)
      uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
    end
  end
end
