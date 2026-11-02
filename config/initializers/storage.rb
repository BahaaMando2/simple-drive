# Build the configured backend at boot so a bad STORAGE_BACKEND or unusable
# path fails on startup instead of on the first request.
Rails.application.config.after_initialize { Storage.backend }
