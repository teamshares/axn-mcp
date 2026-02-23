# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, :development)

require "axn-mcp"
require "axn/testing/spec_helpers"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
