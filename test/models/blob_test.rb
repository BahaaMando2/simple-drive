require "test_helper"

class BlobTest < ActiveSupport::TestCase
  def blob(**attrs)
    Blob.new(id: "a", size: 1, storage_backend: "local", **attrs)
  end

  test "valid with id, size and backend" do
    assert blob.valid?
  end

  test "id limit counts bytes, not characters" do
    assert blob(id: "a" * 1024).valid?
    # 342 three-byte characters = 1026 bytes, under 1024 characters.
    refute blob(id: "€" * 342).valid?
  end

  test "rejects a negative size" do
    refute blob(size: -1).valid?
  end

  test "the database rejects a duplicate id" do
    blob(id: "dup").save!

    assert_raises(ActiveRecord::RecordNotUnique) { blob(id: "dup").save! }
  end

  test "created_at is set automatically" do
    record = blob(id: "ts")
    record.save!

    assert_not_nil record.created_at
  end
end
