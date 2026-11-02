Rails.application.routes.draw do
  # Load balancer health check; deliberately unauthenticated.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :v1, defaults: { format: :json } do
    post "blobs" => "blobs#create"
    # Glob + format: false so ids like "docs/report.pdf" reach the controller intact
    # instead of failing to match on "/" or having ".pdf" parsed as a response format.
    get "blobs/*id" => "blobs#show", format: false, as: :blob
  end
end
