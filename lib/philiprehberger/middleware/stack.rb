# frozen_string_literal: true

module Philiprehberger
  module Middleware
    # A composable middleware stack for processing pipelines.
    #
    # Middleware can be a lambda `(env, next_mw)` or an object responding to `#call(env, next_mw)`.
    class Stack
      # Create a new empty middleware stack.
      def initialize
        @entries = []
      end

      # Append a middleware to the end of the stack.
      #
      # @param middleware [#call, Proc] middleware callable accepting (env, next_mw)
      # @param name [String, Symbol, nil] optional name for insertion/removal
      # @return [self]
      def use(middleware, name: nil)
        validate_middleware!(middleware)
        @entries << Entry.new(middleware: middleware, name: name)
        self
      end

      # Insert a middleware before the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert before
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_before(target_name, middleware, name: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index, Entry.new(middleware: middleware, name: name))
        self
      end

      # Insert a middleware after the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert after
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_after(target_name, middleware, name: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index + 1, Entry.new(middleware: middleware, name: name))
        self
      end

      # Remove a middleware by name.
      #
      # @param target_name [String, Symbol] name of the entry to remove
      # @return [self]
      # @raise [Error] if the target name is not found
      def remove(target_name)
        index = find_index!(target_name)
        @entries.delete_at(index)
        self
      end

      # Execute the middleware stack with the given environment.
      #
      # @param env [Object] the environment/context passed through the stack
      # @return [Object] the final environment after all middleware have run
      def call(env)
        chain = build_chain
        chain.call(env)
      end

      # Return the list of middleware names/entries.
      #
      # @return [Array<String, Symbol, nil>] names of middleware in order
      def to_a
        @entries.map(&:name)
      end

      private

      Entry = Struct.new(:middleware, :name, keyword_init: true)

      def validate_middleware!(middleware)
        raise Error, 'middleware must respond to #call' unless middleware.respond_to?(:call)
      end

      def find_index!(target_name)
        index = @entries.index { |e| e.name == target_name }
        raise Error, "middleware '#{target_name}' not found" unless index

        index
      end

      def build_chain
        # Build from right to left: last middleware calls the terminal,
        # each preceding middleware calls the next one.
        terminal = ->(env) { env }

        @entries.reverse.reduce(terminal) do |next_mw, entry|
          ->(env) { entry.middleware.call(env, next_mw) }
        end
      end
    end
  end
end
