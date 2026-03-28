# frozen_string_literal: true

require_relative 'middleware/version'
require_relative 'middleware/stack'

module Philiprehberger
  module Middleware
    class Error < StandardError; end

    # Raised inside a middleware to halt the chain and return early.
    class Halt < StandardError; end
  end
end
