ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each worker gets its own database already; give it its own blob directory too.
    parallelize_setup do |worker|
      Rails.configuration.x.storage[:local][:path] = "tmp/storage/test-#{worker}"
      Storage.reset!
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
