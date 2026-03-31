# frozen_string_literal: true

require 'set'
require 'timeout'

module Philiprehberger
  module Middleware
    # A composable middleware stack for processing pipelines.
    #
    # Middleware can be a lambda `(env, next_mw)` or an object responding to `#call(env, next_mw)`.
    class Stack
      # Create a new empty middleware stack.
      def initialize
        @entries = []
        @groups = {}
        @disabled_groups = Set.new
        @before_hooks = Hash.new { |h, k| h[k] = [] }
        @after_hooks = Hash.new { |h, k| h[k] = [] }
      end

      # Append a middleware to the end of the stack.
      #
      # @param middleware [#call, Proc] middleware callable accepting (env, next_mw)
      # @param name [String, Symbol, nil] optional name for insertion/removal
      # @param if_opt [Proc, nil] guard -- middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard -- middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @param timeout [Numeric, nil] optional timeout in seconds for middleware execution
      # @return [self]
      def use(middleware, name: nil, if: nil, unless: nil, on_error: nil, timeout: nil)
        validate_middleware!(middleware)
        @entries << Entry.new(
          middleware: middleware,
          name: name,
          if_guard: binding.local_variable_get(:if),
          unless_guard: binding.local_variable_get(:unless),
          on_error: on_error,
          timeout: timeout
        )
        self
      end

      # Insert a middleware before the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert before
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @param if_opt [Proc, nil] guard -- middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard -- middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @param timeout [Numeric, nil] optional timeout in seconds for middleware execution
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_before(target_name, middleware, name: nil, if: nil, unless: nil, on_error: nil, timeout: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index, Entry.new(
                                 middleware: middleware,
                                 name: name,
                                 if_guard: binding.local_variable_get(:if),
                                 unless_guard: binding.local_variable_get(:unless),
                                 on_error: on_error,
                                 timeout: timeout
                               ))
        self
      end

      # Insert a middleware after the named entry.
      #
      # @param target_name [String, Symbol] name of the entry to insert after
      # @param middleware [#call, Proc] middleware callable
      # @param name [String, Symbol, nil] optional name for the new entry
      # @param if_opt [Proc, nil] guard -- middleware runs only when this returns truthy
      # @param unless_opt [Proc, nil] guard -- middleware runs only when this returns falsey
      # @param on_error [Proc, nil] error handler called with (error, env) when the middleware raises
      # @param timeout [Numeric, nil] optional timeout in seconds for middleware execution
      # @return [self]
      # @raise [Error] if the target name is not found
      def insert_after(target_name, middleware, name: nil, if: nil, unless: nil, on_error: nil, timeout: nil)
        validate_middleware!(middleware)
        index = find_index!(target_name)
        @entries.insert(index + 1, Entry.new(
                                     middleware: middleware,
                                     name: name,
                                     if_guard: binding.local_variable_get(:if),
                                     unless_guard: binding.local_variable_get(:unless),
                                     on_error: on_error,
                                     timeout: timeout
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
          on_error: old_entry.on_error,
          timeout: old_entry.timeout
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

      # Define a named group of middleware.
      #
      # @param group_name [Symbol] name of the group
      # @param middleware_names [Array<Symbol>] names of middleware in the group
      # @return [self]
      def group(group_name, middleware_names)
        @groups[group_name] = middleware_names.dup
        self
      end

      # Enable a middleware group.
      #
      # @param group_name [Symbol] name of the group to enable
      # @return [self]
      def enable_group(group_name)
        @disabled_groups.delete(group_name)
        self
      end

      # Disable a middleware group.
      #
      # @param group_name [Symbol] name of the group to disable
      # @return [self]
      def disable_group(group_name)
        @disabled_groups.add(group_name)
        self
      end

      # Check if a middleware group is enabled.
      #
      # @param group_name [Symbol] name of the group
      # @return [Boolean] true if the group is enabled (or not defined as a group)
      def group_enabled?(group_name)
        !@disabled_groups.include?(group_name)
      end

      # Attach a before hook to a named middleware.
      #
      # @param middleware_name [Symbol] name of the middleware to hook
      # @yield [env] block to execute before the middleware
      # @return [self]
      def before(middleware_name, &block)
        @before_hooks[middleware_name] << block
        self
      end

      # Attach an after hook to a named middleware.
      #
      # @param middleware_name [Symbol] name of the middleware to hook
      # @yield [env] block to execute after the middleware
      # @return [self]
      def after(middleware_name, &block)
        @after_hooks[middleware_name] << block
        self
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

      # Remove all middleware entries, groups, and hooks.
      #
      # @return [self]
      def clear
        @entries.clear
        @groups.clear
        @disabled_groups.clear
        @before_hooks.clear
        @after_hooks.clear
        self
      end

      # Swap positions of two named entries.
      #
      # @param name1 [String, Symbol] name of the first entry
      # @param name2 [String, Symbol] name of the second entry
      # @return [self]
      # @raise [Error] if either name is not found
      def swap(name1, name2)
        idx1 = find_index!(name1)
        idx2 = find_index!(name2)
        @entries[idx1], @entries[idx2] = @entries[idx2], @entries[idx1]
        self
      end

      # Return metadata hash about the stack.
      #
      # @return [Hash] count, named, groups, and hooks metadata
      def stats
        {
          count: @entries.length,
          named: @entries.count(&:name),
          groups: @groups.keys,
          hooks: {
            before: @before_hooks.keys,
            after: @after_hooks.keys
          }
        }
      end

      # Return a human-readable stack summary.
      #
      # @return [String] multi-line description of the stack
      def describe
        lines = @entries.map.with_index do |entry, idx|
          parts = ["#{idx}: #{entry.name || '(unnamed)'}"]
          parts << 'if-guarded' if entry.if_guard
          parts << 'unless-guarded' if entry.unless_guard
          parts << "timeout=#{entry.timeout}s" if entry.timeout
          parts << 'on_error' if entry.on_error
          parts.join(' | ')
        end
        lines.join("\n")
      end

      # Return an immutable copy of the stack.
      #
      # @return [FrozenStack] a frozen copy that can execute but not be modified
      def frozen_copy
        FrozenStack.new(@entries.map(&:dup), @groups.dup, @disabled_groups.dup, @before_hooks.dup, @after_hooks.dup)
      end

      # Return the list of middleware names/entries.
      #
      # @return [Array<String, Symbol, nil>] names of middleware in order
      def to_a
        @entries.map(&:name)
      end

      protected

      # Yield each entry -- used internally by merge.
      def each_entry(&)
        @entries.each(&)
      end

      private

      Entry = Struct.new(:middleware, :name, :if_guard, :unless_guard, :on_error, :timeout, keyword_init: true)

      def validate_middleware!(middleware)
        raise Error, 'middleware must respond to #call' unless middleware.respond_to?(:call)
      end

      def find_index!(target_name)
        index = @entries.index { |e| e.name == target_name }
        raise Error, "middleware '#{target_name}' not found" unless index

        index
      end

      def disabled_middleware_names
        names = Set.new
        @disabled_groups.each do |group_name|
          group_members = @groups[group_name]
          group_members&.each { |n| names.add(n) }
        end
        names
      end

      def build_chain(timings: nil)
        disabled = disabled_middleware_names
        terminal = ->(env) { env }

        @entries.reverse.reduce(terminal) do |next_mw, entry|
          if entry.name && disabled.include?(entry.name)
            next_mw
          else
            build_step(entry, next_mw, timings)
          end
        end
      end

      def build_step(entry, next_mw, timings)
        lambda { |env|
          # Halt check -- if env is a Hash and :halt is truthy, stop chain
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

          # Run before hooks
          run_before_hooks(entry.name, env)

          # Execute with optional profiling and error handling
          result = if timings
                     start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                     res = execute_middleware(entry, env, next_mw)
                     end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                     timings << { name: entry.name, duration: end_time - start_time }
                     res
                   else
                     execute_middleware(entry, env, next_mw)
                   end

          # Run after hooks
          run_after_hooks(entry.name, env)

          result
        }
      end

      def run_before_hooks(name, env)
        return unless name

        @before_hooks[name].each { |hook| hook.call(env) }
      end

      def run_after_hooks(name, env)
        return unless name

        @after_hooks[name].each { |hook| hook.call(env) }
      end

      def execute_middleware(entry, env, next_mw)
        if entry.timeout
          execute_with_timeout(entry, env, next_mw)
        else
          entry.middleware.call(env, next_mw)
        end
      rescue Halt => e
        raise e
      rescue Philiprehberger::Middleware::TimeoutError => e
        raise e
      rescue StandardError => e
        raise e unless entry.on_error

        entry.on_error.call(e, env)
        next_mw.call(env)
      end

      def execute_with_timeout(entry, env, next_mw)
        Timeout.timeout(entry.timeout, Philiprehberger::Middleware::TimeoutError,
                        "middleware '#{entry.name}' exceeded #{entry.timeout}s timeout") do
          entry.middleware.call(env, next_mw)
        end
      end
    end

    # An immutable snapshot of a middleware stack that can execute but not be modified.
    class FrozenStack
      def initialize(entries, groups, disabled_groups, before_hooks, after_hooks)
        @entries = entries.freeze
        @groups = groups.freeze
        @disabled_groups = disabled_groups.freeze
        @before_hooks = before_hooks.freeze
        @after_hooks = after_hooks.freeze
      end

      # Execute the frozen middleware stack with the given environment.
      #
      # @param env [Object] the environment/context passed through the stack
      # @return [Object] the final environment after all middleware have run
      def call(env)
        disabled = disabled_middleware_names
        terminal = ->(e) { e }
        chain = @entries.reverse.reduce(terminal) do |next_mw, entry|
          if entry.name && disabled.include?(entry.name)
            next_mw
          else
            build_frozen_step(entry, next_mw)
          end
        end
        chain.call(env)
      rescue Philiprehberger::Middleware::Halt
        env
      end

      # Return the list of middleware names.
      #
      # @return [Array<String, Symbol, nil>] names of middleware in order
      def to_a
        @entries.map(&:name)
      end

      # Look up an entry by name.
      #
      # @param target_name [String, Symbol] name of the entry
      # @return [#call, nil] the middleware callable, or nil if not found
      def [](target_name)
        entry = @entries.find { |e| e.name == target_name }
        entry&.middleware
      end

      %i[use insert_before insert_after remove replace clear swap merge group enable_group disable_group before
         after].each do |method|
        define_method(method) { |*| raise Philiprehberger::Middleware::Error, 'cannot modify a frozen stack' }
      end

      private

      def disabled_middleware_names
        names = Set.new
        @disabled_groups.each do |group_name|
          group_members = @groups[group_name]
          group_members&.each { |n| names.add(n) }
        end
        names
      end

      def build_frozen_step(entry, next_mw)
        lambda { |env|
          return env if env.is_a?(Hash) && env[:halt]
          return next_mw.call(env) if entry.if_guard && !entry.if_guard.call
          return next_mw.call(env) if entry.unless_guard&.call

          entry.middleware.call(env, next_mw)
        }
      end
    end
  end
end
