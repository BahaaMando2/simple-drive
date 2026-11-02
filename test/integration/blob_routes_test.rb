require "test_helper"

class BlobRoutesTest < ActionDispatch::IntegrationTest
  test "ids containing slashes and dots route intact" do
    assert_recognizes(
      { controller: "v1/blobs", action: "show", id: "docs/2023/report.final.pdf", format: :json },
      "/v1/blobs/docs/2023/report.final.pdf"
    )
  end

  test "percent-encoded ids are decoded" do
    assert_recognizes(
      { controller: "v1/blobs", action: "show", id: "my file?.txt", format: :json },
      "/v1/blobs/my%20file%3F.txt"
    )
  end
end
