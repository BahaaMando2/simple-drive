require "test_helper"

class Storage::DatabaseBackendTest < ActiveSupport::TestCase
  include StorageBackendContract

  def backend
    @backend ||= Storage::DatabaseBackend.new
  end

  test "rolls back with the caller's transaction" do
    Blob.transaction do
      backend.put("rolled-back", "bytes")
      raise ActiveRecord::Rollback
    end

    assert_raises(Storage::NotFound) { backend.get("rolled-back") }
  end

  test "is selectable by name from config" do
    assert_instance_of Storage::DatabaseBackend, Storage.backend("database")
  end
end
