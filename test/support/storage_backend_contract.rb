# The behaviour every storage backend must provide. Include this in a backend's
# test case and define #backend; the same tests then run against that backend.
module StorageBackendContract
  extend ActiveSupport::Concern

  included do
    test "contract: returns exactly the bytes stored, as binary" do
      bytes = (0..255).to_a.pack("C*") # every byte value, incl. NUL and invalid UTF-8
      backend.put("binary", bytes)

      result = backend.get("binary")
      assert_equal Encoding::BINARY, result.encoding
      assert_equal bytes, result
    end

    test "contract: stores an empty blob" do
      backend.put("empty", "")

      assert_equal "", backend.get("empty")
    end

    test "contract: similar or path-like ids never collide" do
      # Includes ids that broke raw S3 keys on MinIO: dot segments, "//", and
      # "/leading" vs "leading", which silently shared one key.
      ids = [ "a/b", "a_b", "A/B", "a/b/", "a//b", "../a/b", "./a", "..", "leading", "/leading", "مرحبا/ملف.txt" ]
      ids.each { |id| backend.put(id, "value of #{id}".b) }

      ids.each { |id| assert_equal "value of #{id}".b, backend.get(id) }
    end

    test "contract: put overwrites an existing value" do
      backend.put("same", "first")
      backend.put("same", "second")

      assert_equal "second", backend.get("same")
    end

    test "contract: unknown id raises Storage::NotFound" do
      assert_raises(Storage::NotFound) { backend.get("never-stored") }
    end
  end
end
