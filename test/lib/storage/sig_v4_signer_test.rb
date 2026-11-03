require "test_helper"

# Expected values are copied verbatim from AWS's official SigV4 test suite
# (published in botocore: tests/unit/auth/aws4_testsuite/<name>/<name>.creq|.sts|.authz).
class Storage::SigV4SignerTest < ActiveSupport::TestCase
  TIME = Time.utc(2015, 8, 30, 12, 36, 0)
  EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".freeze

  def signer
    Storage::SigV4Signer.new(
      access_key_id: "AKIDEXAMPLE",
      secret_access_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
      region: "us-east-1",
      service: "service"
    )
  end

  def authorization(method, path, body: "", headers: {})
    signer.sign(method: method, uri: URI("https://example.amazonaws.com#{path}"),
                payload_sha256: Digest::SHA256.hexdigest(body), headers: headers, time: TIME)["authorization"]
  end

  test "get-vanilla: every step matches AWS" do
    headers = { "host" => "example.amazonaws.com", "x-amz-date" => "20150830T123600Z" }
    canonical = signer.canonical_request("GET", URI("https://example.amazonaws.com/"), headers, EMPTY_SHA256)

    assert_equal <<~CREQ.chomp, canonical
      GET
      /

      host:example.amazonaws.com
      x-amz-date:20150830T123600Z

      host;x-amz-date
      #{EMPTY_SHA256}
    CREQ

    assert_equal <<~STS.chomp, signer.string_to_sign("20150830T123600Z", canonical)
      AWS4-HMAC-SHA256
      20150830T123600Z
      20150830/us-east-1/service/aws4_request
      bb579772317eb040ac9ed261061d46c1f17a8133879d6129b6e1c25292927e63
    STS

    assert_equal "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, " \
                 "SignedHeaders=host;x-amz-date, " \
                 "Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31",
                 authorization("GET", "/")
  end

  test "get-utf8: non-ASCII path is percent-encoded byte by byte" do
    path = Storage::SigV4Signer.uri_encode("/ሴ", encode_slash: false)

    assert_equal "/%E1%88%B4", path
    assert_match(/Signature=8318018e0b0f223aa2bbf98705b62bb787dc9c0e678f255a891fd03141be5d85\z/,
                 authorization("GET", path))
  end

  test "post-x-www-form-urlencoded: extra headers and the body hash are signed" do
    auth = authorization("POST", "/", body: "Param1=value1",
                         headers: { "Content-Type" => "application/x-www-form-urlencoded" })

    assert_match(/SignedHeaders=content-type;host;x-amz-date, /, auth)
    assert_match(/Signature=ff11897932ad3f4e8b18135d722051e5ac45fc38421b1da7b9d196a0fe09473a\z/, auth)
  end

  test "changing anything signed changes the signature" do
    base = authorization("GET", "/a")

    refute_equal base, authorization("GET", "/b")
    refute_equal base, authorization("PUT", "/a")
    refute_equal base, authorization("GET", "/a", body: "x")
  end

  test "uri_encode leaves only unreserved characters" do
    assert_equal "a%20b%2Fc~d-e_f.g", Storage::SigV4Signer.uri_encode("a b/c~d-e_f.g")
    assert_equal "docs/my%20file%3F.txt", Storage::SigV4Signer.uri_encode("docs/my file?.txt", encode_slash: false)
  end

  test "non-default ports are part of the signed host" do
    headers = signer.sign(method: "GET", uri: URI("http://minio:9000/b/k"), payload_sha256: EMPTY_SHA256, time: TIME)

    assert_equal "minio:9000", headers["host"]
  end
end
