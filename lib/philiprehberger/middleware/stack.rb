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
      # @param if_opt [Proc, nil] guard — middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard — middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @return [self]
      def use(middleware, name: nil, if: nil, unless: nil, on_error: nil)
        validate_middleware!(middleware)
        @entries << Entry.new(
          middleware: middleware,
          name: name,
          if_guard: binding.local_variable_get(:if),
          unless_guard: binding.local_variable_get(:unless),
          on_error: on_error
        )
        self
      end

      # Insert a middleware before the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert before
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @param if_opt [Proc, nil] guard — middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard — middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_before(target_name, middleware, name: nil, if: nil, unless: nil, on_error: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index, Entry.new(
                                 middleware: middleware,
                                 name: name,
                                 if_guard: binding.local_variable_get(:if),
                                 unless_guard: binding.local_variable_get(:unless),
                                 on_error: on_error
                               ))
        self
      end

      # Insert a middleware after the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert after
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @param if_opt [Proc, nil] guard — middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard — middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_after(target_name, middleware, name: nil, if: nil, unless: nil, on_error: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index + 1, Entry.new(
                                     middleware: middleware,
                                     name: name,
                                     if_guard: binding.local_variable_get(:if),
                                     unless_guard: binding.local_variable_get(:unless),
                                     on_error: on_error
                                   ))
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

      # Replace a named middleware with a new one.
      #
      # @param target_name [String, Symbol] name of the entry to replace
      # @param middleware [#call, Proc] the replacement middleware
      # @param name [String, Symbol, nil] optional new name (defaults to existing name)
      # @return [self]
      # @raise [Error] if the target name is not found
      def replace(target_name, middleware, name: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        old_entry = @entries[index]
        @entries[index] = Entry.new(
          middleware: middleware,
          name: name || old_entry.name,
          if_guard: old_entry.if_guard,
          unless_guard: old_entry.unless_guard,
          on_error: old_entry.on_error
        )
        self
      end

      # Look up an entry by name.
      #
      # @param target_name [String, Symbol] name of the entry
      # @return [#call, nil] the middleware callable, or nil if not found
      def [](target_name)
        entry = @entries.find { |e| e.name == target_name }
        entry&.middleware
      end

      # Execute the middleware stack with the given environment.
      #
      # @param env [Object] the environment/context passed through the stack
      # @return [Object] the final environment after all middleware have run
      def call(env)
        chain = build_chain
        chain.call(env)
      rescue Halt
        env
      end

      # Execute the middleware stack and return profiling data.
      #
      # @param env [Object] the environment/context passed through the stack
      # @return [Hash] { result: <env>, timings: [{ name:, duration: }, ...] }
      def profile(env)
        timings = []
        chain = build_chain(timings: timings)
        result = chain.call(env)
        { result: result, timings: timings }
      rescue Halt
        { result: env, timings: timings }
      end

      # Merge another stack's entries onto the end of this stack.
      #
      # @param other [Stack] the stack to merge from
      # @return [self]
      def merge(other)
        raise Error, 'argument must be a Stack' unless other.is_a?(Stack)

        other.each_entry { |entry| @entries << entry.dup }
        self
      end

      # Return the list of middleware names/entries.
      #
      # @return [Array<String, Symbol, nil>] names of middleware in order
      def to_a
        @entries.map(&:name)
      end

      protected

      # Yield each entry — used internally by merge.
      def each_entry(&)
        @entries.each(&)
      end

      private

      Entry = Struct.new(:middleware, :name, :if_guard, :unless_guard, :on_error, keyword_init: true)

      def validate_middleware!(middleware)
        raise Error, 'middleware must respond to #call' unless middleware.respond_to?(:call)
      end

      def find_index!(target_name)
        index = @entries.index { |e| e.name == target_name }
        raise Error, "middleware '#{target_name}' not found" unless index

        index
      end

      def build_chain(timings: nil)
        # Build from right to left: last middleware calls the terminal,
        # each preceding middleware calls the next one.
        terminal = ->(env) { env }

        @entries.reverse.reduce(terminal) do |next_mw, entry|
          build_step(entry, next_mw, timings)
        end
      end

      def build_step(entry, next_mw, timings)
        lambda { |env|
          # Halt check — if env is a Hash and :halt is truthy, stop chain
          if env.is_a?(Hash) && env[:halt]
            return env
          end

          # Conditional guards
          if entry.if_guard && !entry.if_guard.call
            return next_mw.call(env)
          end

          if entry.unless_guard&.call
            return next_mw.call(env)
          end

          # Execute with optional profiling and error handling
          if timings
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = execute_middleware(entry, env, next_mw)
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            timings << { name: entry.name, duration: end_time - start_time }
            result
          else
            execute_middleware(entry, env, next_mw)
          end
        }
      end

      def execute_middleware(entry, env, next_mw)
        entry.middleware.call(env, next_mw)
      rescue Halt => e
        raise e
      rescue StandardError => e
        raise e unless entry.on_error

        entry.on_error.call(e, env)
        next_mw.call(env)
      end
    end
  end
end
