# Metadata only; the blob bytes live in the configured storage backend.
class CreateBlobs < ActiveRecord::Migration[8.1]
  def change
    # The client-chosen id is the primary key: its uniqueness is then enforced by
    # the database itself, which stays correct under concurrent POSTs.
    create_table :blobs, id: :string do |t|
      t.bigint :size, null: false
      t.string :storage_backend, null: false
      # Blobs are immutable, so there is no updated_at.
      t.datetime :created_at, null: false
    end
  end
end
