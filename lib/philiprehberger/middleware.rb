# frozen_string_literal: true

require_relative 'middleware/version'
require_relative 'middleware/stack'

module Philiprehberger
  module Middleware
    class Error < StandardError; end
  end
end
