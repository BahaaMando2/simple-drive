require "test_helper"

class Storage::LocalBackendTest < ActiveSupport::TestCase
  include StorageBackendContract

  attr_reader :backend

  setup do
    @dir = Dir.mktmpdir
    @root = File.join(@dir, "blobs")
    @backend = Storage::LocalBackend.new(path: @root)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "creates the storage directory if missing" do
    assert File.directory?(@root)
  end

  test "path traversal ids stay inside the root" do
    backend.put("../../escaped", "x")

    assert_equal [ "blobs" ], Dir.children(@dir)
    assert_equal 1, Dir.children(@root).size
    refute File.exist?(File.join(@dir, "escaped"))
  end

  test "wraps filesystem failures in Storage::Error" do
    FileUtils.rm_rf(@root)
    File.write(@root, "a file where the directory should be")

    assert_raises(Storage::Error) { backend.put("id", "x") }
  end
end
