require "base64"

module V1
  class BlobsController < ApplicationController
    rescue_from Storage::Error do |error|
      Rails.logger.error("Storage backend failed: #{error.class}: #{error.message}")
      render_error "storage backend failed", :bad_gateway
    end

    def create
      id = params[:id]
      return render_error("id must be a string", :unprocessable_content) unless id.is_a?(String)

      bytes = decode_base64(params[:data])
      return render_error("data must be a valid Base64 string", :unprocessable_content) unless bytes

      blob = Blob.new(id: id, size: bytes.bytesize, storage_backend: Storage.default_name)
      return render_error(blob.errors.full_messages.to_sentence, :unprocessable_content) unless blob.valid?

      # Row first, then bytes, in one transaction: a duplicate id fails on the
      # primary key before anything is written, and a failed write rolls the row
      # back, so metadata never points at missing data.
      Blob.transaction do
        blob.save!
        Storage.backend(blob.storage_backend).put(blob.id, bytes)
      end

      render json: blob_json(blob), status: :created, location: v1_blob_url(blob.id)
    rescue ActiveRecord::RecordNotUnique
      render_error "a blob with this id already exists", :conflict
    end

    def show
      blob = Blob.find_by(id: params[:id])
      return render_error("blob not found", :not_found) unless blob

      bytes = Storage.backend(blob.storage_backend).get(blob.id)
      render json: blob_json(blob, bytes)
    end

    private

    # strict_decode64, not decode64: decode64 silently skips invalid characters,
    # so garbage would be stored instead of rejected.
    def decode_base64(data)
      Base64.strict_decode64(data) if data.is_a?(String)
    rescue ArgumentError
      nil
    end

    def blob_json(blob, bytes = nil)
      {
        id: blob.id,
        data: bytes && Base64.strict_encode64(bytes),
        size: blob.size.to_s,
        created_at: blob.created_at.utc.iso8601
      }.compact
    end
  end
end
