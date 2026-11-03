class Blob < ApplicationRecord
  # Same limit as S3 object keys, so any accepted id can be stored on every backend.
  MAX_ID_BYTES = 1024

  validates :id, presence: true
  validates :size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :storage_backend, presence: true
  validate :id_within_byte_limit
  # JSON allows "\u0000" in strings, but Postgres text can't hold it.
  validates :id, format: { without: /\0/, message: "must not contain NUL characters" }

  private

  def id_within_byte_limit
    errors.add(:id, "is too long (maximum is #{MAX_ID_BYTES} bytes)") if id.to_s.bytesize > MAX_ID_BYTES
  end
end
