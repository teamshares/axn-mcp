# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default, :development)

require "axn-mcp"
require "axn/testing/spec_helpers"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

# The legacy annotation bang-methods (read_only!/destructive!/etc., see lib/axn/mcp/tool.rb) emit a
# real deprecation warning on every call -- silence it for the suite by default so specs exercising
# those methods for their annotation-setting behavior (not the deprecation itself) stay pristine.
# Specs that assert the warning fires do so via a plain RSpec mock on Axn::MCP.deprecator, which
# intercepts the call before this behavior setting is ever consulted.
Axn::MCP.deprecator.behavior = :silence

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
