# Storage table for the database backend. Separate from the blobs metadata table
# and deliberately not linked to it: a backend only knows ids and bytes.
class CreateBlobContents < ActiveRecord::Migration[8.1]
  def change
    create_table :blob_contents, id: :string do |t|
      t.binary :data, null: false # bytea: raw bytes, not Base64
    end
  end
end
