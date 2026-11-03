# Storage backends hold blob bytes; the blobs table holds only metadata.
#
# Every backend implements the same two methods:
#   put(id, bytes)  stores bytes under id, overwriting anything already there
#   get(id)         returns the bytes (binary String) or raises Storage::NotFound
#
# Backends own the mapping from id to their native key, so ids are never trusted
# as filenames or paths. test/support/storage_backend_contract.rb is the
# executable version of this interface: every backend must pass it.
module Storage
  class Error < StandardError; end
  class NotFound < Error; end

  BACKENDS = {
    "local" => LocalBackend,
    "database" => DatabaseBackend,
    "s3" => S3Backend
  }.freeze

  class << self
    # The backend called name, built once from config/storage.yml.
    # Defaults to the one new blobs are written to.
    def backend(name = default_name)
      @backends ||= {}
      @backends[name] ||= build(name)
    end

    def default_name
      config.fetch(:backend)
    end

    def reset!
      @backends = nil
    end

    private

    def config
      Rails.configuration.x.storage
    end

    def build(name)
      klass = BACKENDS.fetch(name) do
        raise ArgumentError, "Unknown storage backend #{name.inspect}. Use one of: #{BACKENDS.keys.join(", ")}"
      end
      klass.new(**config.fetch(name.to_sym, {}))
    end
  end
end
