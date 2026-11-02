require "digest"

module Storage
  # Stores each blob as one file named by the SHA-256 of its id.
  # Hashing means any id ("../../etc/passwd", "a/b", unicode) maps to a safe,
  # fixed-length filename inside the root, and distinct ids never collide.
  class LocalBackend
    def initialize(path:)
      @root = Rails.root.join(path)
      FileUtils.mkdir_p(@root)
    end

    def put(id, bytes)
      File.binwrite(path_for(id), bytes)
    rescue SystemCallError => e
      raise Error, "local write failed: #{e.message}"
    end

    def get(id)
      File.binread(path_for(id))
    rescue Errno::ENOENT
      raise NotFound, "no local file for blob"
    rescue SystemCallError => e
      raise Error, "local read failed: #{e.message}"
    end

    private

    def path_for(id)
      @root.join(Digest::SHA256.hexdigest(id))
    end
  end
end
