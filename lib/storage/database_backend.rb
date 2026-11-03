module Storage
  # Stores blob bytes as rows in the blob_contents table of the app's database.
  # Because it shares the app's connection, a put inside the controller's
  # transaction is rolled back together with the metadata row.
  class DatabaseBackend
    class Content < ApplicationRecord
      self.table_name = "blob_contents"
    end

    def put(id, bytes)
      Content.upsert({ id: id, data: bytes }, unique_by: :id)
    rescue ActiveRecord::ActiveRecordError => e
      raise Error, "database write failed: #{e.message}"
    end

    def get(id)
      Content.where(id: id).pick(:data) or raise NotFound, "no database row for blob"
    rescue ActiveRecord::ActiveRecordError => e
      raise Error, "database read failed: #{e.message}"
    end
  end
end
