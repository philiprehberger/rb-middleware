# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::Middleware do
  describe 'VERSION' do
    it 'has a version number' do
      expect(Philiprehberger::Middleware::VERSION).not_to be_nil
    end
  end

  describe 'Halt' do
    it 'is a subclass of StandardError' do
      expect(Philiprehberger::Middleware::Halt.new).to be_a(StandardError)
    end
  end

  describe 'TimeoutError' do
    it 'is a subclass of Error' do
      expect(Philiprehberger::Middleware::TimeoutError.new).to be_a(Philiprehberger::Middleware::Error)
    end
  end
end

RSpec.describe Philiprehberger::Middleware::Stack do
  let(:stack) { described_class.new }

  describe '#use' do
    it 'adds middleware to the stack' do
      mw = ->(env, next_mw) { next_mw.call(env) }
      stack.use(mw, name: :logger)
      expect(stack.to_a).to eq([:logger])
    end

    it 'raises if middleware does not respond to call' do
      expect { stack.use('not callable') }
        .to raise_error(Philiprehberger::Middleware::Error, /call/)
    end

    it 'returns self for chaining' do
      mw = ->(env, next_mw) { next_mw.call(env) }
      expect(stack.use(mw)).to eq(stack)
    end
  end

  describe '#call' do
    it 'passes env through the stack' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(a: 1)) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(b: 2)) }, name: :second)

      result = stack.call({})
      expect(result).to eq({ a: 1, b: 2 })
    end

    it 'executes middleware in order' do
      order = []
      stack.use(lambda { |env, next_mw|
        order << :first
        next_mw.call(env)
      }, name: :first)
      stack.use(lambda { |env, next_mw|
        order << :second
        next_mw.call(env)
      }, name: :second)

      stack.call({})
      expect(order).to eq(%i[first second])
    end

    it 'returns env when stack is empty' do
      expect(stack.call({ key: 'value' })).to eq({ key: 'value' })
    end

    it 'allows middleware to short-circuit' do
      stack.use(->(env, _next_mw) { env.merge(stopped: true) }, name: :stopper)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(reached: true)) }, name: :after)

      result = stack.call({})
      expect(result).to eq({ stopped: true })
    end

    it 'works with class-based middleware' do
      klass = Class.new do
        def call(env, next_mw)
          next_mw.call(env.merge(class_based: true))
        end
      end

      stack.use(klass.new, name: :class_mw)
      result = stack.call({})
      expect(result).to eq({ class_based: true })
    end
  end

  describe '#insert_before' do
    it 'inserts middleware before the named entry' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :last)
      stack.insert_before(:last, ->(env, next_mw) { next_mw.call(env) }, name: :middle)

      expect(stack.to_a).to eq(%i[first middle last])
    end

    it 'raises if target not found' do
      expect { stack.insert_before(:missing, ->(e, n) { n.call(e) }) }
        .to raise_error(Philiprehberger::Middleware::Error, /not found/)
    end
  end

  describe '#insert_after' do
    it 'inserts middleware after the named entry' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :last)
      stack.insert_after(:first, ->(env, next_mw) { next_mw.call(env) }, name: :middle)

      expect(stack.to_a).to eq(%i[first middle last])
    end

    it 'raises if target not found' do
      expect { stack.insert_after(:missing, ->(e, n) { n.call(e) }) }
        .to raise_error(Philiprehberger::Middleware::Error, /not found/)
    end
  end

  describe '#remove' do
    it 'removes middleware by name' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :second)
      stack.remove(:first)

      expect(stack.to_a).to eq([:second])
    end

    it 'raises if name not found' do
      expect { stack.remove(:missing) }
        .to raise_error(Philiprehberger::Middleware::Error, /not found/)
    end
  end

  describe '#to_a' do
    it 'returns names in order' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :a)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :b)
      stack.use(->(env, next_mw) { next_mw.call(env) })

      expect(stack.to_a).to eq([:a, :b, nil])
    end
  end

  describe 'middleware transforms env in correct order' do
    it 'applies transformations sequentially' do
      stack.use(->(env, next_mw) { next_mw.call(env + [1]) }, name: :add_one)
      stack.use(->(env, next_mw) { next_mw.call(env + [2]) }, name: :add_two)
      stack.use(->(env, next_mw) { next_mw.call(env + [3]) }, name: :add_three)

      result = stack.call([])
      expect(result).to eq([1, 2, 3])
    end
  end

  # --- Expanded tests ---

  describe 'empty stack behavior' do
    it 'returns the exact same object type passed in' do
      expect(stack.call('hello')).to eq('hello')
      expect(stack.call(42)).to eq(42)
      expect(stack.call([1, 2])).to eq([1, 2])
    end
  end

  describe 'insert_before at the beginning' do
    it 'inserts before the first entry' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :original)
      stack.insert_before(:original, ->(env, next_mw) { next_mw.call(env) }, name: :new_first)
      expect(stack.to_a).to eq(%i[new_first original])
    end

    it 'executes inserted middleware first' do
      order = []
      stack.use(lambda { |env, next_mw|
        order << :original
        next_mw.call(env)
      }, name: :original)
      stack.insert_before(:original, lambda { |env, next_mw|
        order << :inserted
        next_mw.call(env)
      }, name: :inserted)

      stack.call({})
      expect(order).to eq(%i[inserted original])
    end
  end

  describe 'insert_after at the end' do
    it 'inserts after the last entry' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
      stack.insert_after(:first, ->(env, next_mw) { next_mw.call(env) }, name: :second)
      expect(stack.to_a).to eq(%i[first second])
    end
  end

  describe 'remove and re-add' do
    it 'allows re-adding middleware after removal' do
      mw = ->(env, next_mw) { next_mw.call(env) }
      stack.use(mw, name: :temp)
      stack.remove(:temp)
      stack.use(mw, name: :temp)
      expect(stack.to_a).to eq([:temp])
    end
  end

  describe 'middleware mutation of env' do
    it 'allows middleware to mutate shared env hash' do
      stack.use(lambda { |env, next_mw|
        env[:counter] = (env[:counter] || 0) + 1
        next_mw.call(env)
      }, name: :increment)
      stack.use(lambda { |env, next_mw|
        env[:counter] = (env[:counter] || 0) + 10
        next_mw.call(env)
      }, name: :add_ten)

      result = stack.call({})
      expect(result[:counter]).to eq(11)
    end
  end

  describe 'short-circuit prevents downstream execution' do
    it 'downstream middleware does not execute' do
      executed = []
      stack.use(lambda { |env, _next_mw|
        executed << :stopper
        env
      }, name: :stopper)
      stack.use(lambda { |env, next_mw|
        executed << :after
        next_mw.call(env)
      }, name: :after)

      stack.call({})
      expect(executed).to eq([:stopper])
    end
  end

  describe 'middleware without names' do
    it 'allows multiple unnamed middleware' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(a: 1)) })
      stack.use(->(env, next_mw) { next_mw.call(env.merge(b: 2)) })
      result = stack.call({})
      expect(result).to eq({ a: 1, b: 2 })
      expect(stack.to_a).to eq([nil, nil])
    end
  end

  describe 'chaining use calls' do
    it 'supports method chaining with use' do
      result = stack
               .use(->(env, next_mw) { next_mw.call(env.merge(x: 1)) }, name: :x)
               .use(->(env, next_mw) { next_mw.call(env.merge(y: 2)) }, name: :y)
               .call({})
      expect(result).to eq({ x: 1, y: 2 })
    end
  end

  describe 'chaining insert_before' do
    it 'returns self from insert_before' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      result = stack.insert_before(:target, ->(env, next_mw) { next_mw.call(env) }, name: :new)
      expect(result).to eq(stack)
    end
  end

  describe 'chaining insert_after' do
    it 'returns self from insert_after' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      result = stack.insert_after(:target, ->(env, next_mw) { next_mw.call(env) }, name: :new)
      expect(result).to eq(stack)
    end
  end

  describe 'chaining remove' do
    it 'returns self from remove' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      result = stack.remove(:target)
      expect(result).to eq(stack)
    end
  end

  describe 'class-based middleware with state' do
    it 'can maintain state across calls' do
      klass = Class.new do
        attr_reader :call_count

        def initialize
          @call_count = 0
        end

        def call(env, next_mw)
          @call_count += 1
          next_mw.call(env.merge(calls: @call_count))
        end
      end

      mw = klass.new
      stack.use(mw, name: :counter)
      stack.call({})
      stack.call({})
      result = stack.call({})
      expect(result[:calls]).to eq(3)
      expect(mw.call_count).to eq(3)
    end
  end

  # --- Conditional middleware tests ---

  describe 'conditional middleware (if/unless guards)' do
    describe 'if: guard' do
      it 'executes middleware when if condition is true' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { true }
        )

        result = stack.call({})
        expect(result).to eq({ ran: true })
      end

      it 'skips middleware when if condition is false' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { false }
        )

        result = stack.call({})
        expect(result).to eq({})
      end

      it 'still calls downstream middleware when skipped' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(first: true)) },
          name: :skipped,
          if: -> { false }
        )
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(second: true)) },
          name: :kept
        )

        result = stack.call({})
        expect(result).to eq({ second: true })
      end

      it 'evaluates the guard each time call is invoked' do
        counter = 0
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { (counter += 1).odd? }
        )

        expect(stack.call({})).to eq({ ran: true })
        expect(stack.call({})).to eq({})
        expect(stack.call({})).to eq({ ran: true })
      end
    end

    describe 'unless: guard' do
      it 'executes middleware when unless condition is false' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          unless: -> { false }
        )

        result = stack.call({})
        expect(result).to eq({ ran: true })
      end

      it 'skips middleware when unless condition is true' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          unless: -> { true }
        )

        result = stack.call({})
        expect(result).to eq({})
      end
    end

    describe 'if: and unless: combined' do
      it 'runs when if is true and unless is false' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { true },
          unless: -> { false }
        )

        expect(stack.call({})).to eq({ ran: true })
      end

      it 'skips when if is false even if unless is false' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { false },
          unless: -> { false }
        )

        expect(stack.call({})).to eq({})
      end

      it 'skips when unless is true even if if is true' do
        stack.use(
          ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
          name: :guarded,
          if: -> { true },
          unless: -> { true }
        )

        expect(stack.call({})).to eq({})
      end
    end

    it 'supports guards on insert_before' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(original: true)) }, name: :original)
      stack.insert_before(
        :original,
        ->(env, next_mw) { next_mw.call(env.merge(inserted: true)) },
        name: :inserted,
        if: -> { false }
      )

      result = stack.call({})
      expect(result).to eq({ original: true })
    end

    it 'supports guards on insert_after' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(original: true)) }, name: :original)
      stack.insert_after(
        :original,
        ->(env, next_mw) { next_mw.call(env.merge(inserted: true)) },
        name: :inserted,
        unless: -> { true }
      )

      result = stack.call({})
      expect(result).to eq({ original: true })
    end
  end

  describe 'error handling (on_error)' do
    it 'calls on_error handler when middleware raises' do
      errors = []
      stack.use(
        ->(_env, _next_mw) { raise 'boom' },
        name: :raiser,
        on_error: ->(error, _env) { errors << error.message }
      )

      stack.call({})
      expect(errors).to eq(['boom'])
    end

    it 'continues the chain after on_error handles the error' do
      stack.use(
        ->(_env, _next_mw) { raise 'boom' },
        name: :raiser,
        on_error: ->(_error, _env) {}
      )
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(reached: true)) },
        name: :after
      )

      result = stack.call({})
      expect(result).to eq({ reached: true })
    end

    it 'raises the error when no on_error is set' do
      stack.use(->(_env, _next_mw) { raise 'no handler' }, name: :raiser)

      expect { stack.call({}) }.to raise_error(RuntimeError, 'no handler')
    end

    it 'receives both the error and the env' do
      captured_env = nil
      stack.use(
        ->(_env, _next_mw) { raise 'test' },
        name: :raiser,
        on_error: ->(_error, env) { captured_env = env }
      )

      stack.call({ request_id: 42 })
      expect(captured_env).to eq({ request_id: 42 })
    end

    it 'does not catch Halt exceptions in on_error' do
      stack.use(
        ->(_env, _next_mw) { raise Philiprehberger::Middleware::Halt },
        name: :halter,
        on_error: ->(_error, _env) {}
      )
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(reached: true)) },
        name: :after
      )

      result = stack.call({})
      expect(result).to eq({})
      expect(result).not_to have_key(:reached)
    end
  end

  describe 'halt mechanism' do
    describe 'env[:halt]' do
      it 'stops the chain when env[:halt] is set to true' do
        executed = []
        stack.use(lambda { |env, next_mw|
          executed << :first
          next_mw.call(env.merge(halt: true, first: true))
        }, name: :first)
        stack.use(lambda { |env, next_mw|
          executed << :second
          next_mw.call(env.merge(second: true))
        }, name: :second)

        result = stack.call({})
        expect(executed).to eq([:first])
        expect(result).to eq({ halt: true, first: true })
      end

      it 'does not halt when env[:halt] is false' do
        stack.use(->(env, next_mw) { next_mw.call(env.merge(halt: false, a: 1)) }, name: :first)
        stack.use(->(env, next_mw) { next_mw.call(env.merge(b: 2)) }, name: :second)

        result = stack.call({})
        expect(result).to eq({ halt: false, a: 1, b: 2 })
      end

      it 'does not halt when env is not a hash' do
        stack.use(->(env, next_mw) { next_mw.call(env + [1]) }, name: :first)
        stack.use(->(env, next_mw) { next_mw.call(env + [2]) }, name: :second)

        result = stack.call([])
        expect(result).to eq([1, 2])
      end
    end

    describe 'Halt exception' do
      it 'stops execution and returns the env' do
        executed = []
        stack.use(lambda { |_env, _next_mw|
          executed << :halter
          raise Philiprehberger::Middleware::Halt
        }, name: :halter)
        stack.use(lambda { |env, next_mw|
          executed << :after
          next_mw.call(env)
        }, name: :after)

        result = stack.call({ data: 'value' })
        expect(executed).to eq([:halter])
        expect(result).to eq({ data: 'value' })
      end

      it 'returns original env when Halt is raised in first middleware' do
        stack.use(->(_env, _next_mw) { raise Philiprehberger::Middleware::Halt }, name: :halter)

        result = stack.call({ original: true })
        expect(result).to eq({ original: true })
      end
    end
  end

  describe '#profile' do
    it 'returns result and timings' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(a: 1)) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(b: 2)) }, name: :second)

      output = stack.profile({})
      expect(output[:result]).to eq({ a: 1, b: 2 })
      expect(output[:timings]).to be_an(Array)
      expect(output[:timings].length).to eq(2)
    end

    it 'includes timing data for each middleware' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :fast)

      output = stack.profile({})
      timing = output[:timings].first
      expect(timing[:name]).to eq(:fast)
      expect(timing[:duration]).to be_a(Float)
      expect(timing[:duration]).to be >= 0
    end

    it 'records durations that reflect actual time spent' do
      stack.use(lambda { |env, next_mw|
        sleep(0.01)
        next_mw.call(env)
      }, name: :slow)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :fast)

      output = stack.profile({})
      slow_timing = output[:timings].find { |t| t[:name] == :slow }
      fast_timing = output[:timings].find { |t| t[:name] == :fast }

      expect(slow_timing[:duration]).to be > fast_timing[:duration]
    end

    it 'handles empty stack' do
      output = stack.profile({ key: 'value' })
      expect(output[:result]).to eq({ key: 'value' })
      expect(output[:timings]).to eq([])
    end

    it 'respects conditional guards during profiling' do
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
        name: :skipped,
        if: -> { false }
      )
      stack.use(->(env, next_mw) { next_mw.call(env.merge(kept: true)) }, name: :kept)

      output = stack.profile({})
      expect(output[:result]).to eq({ kept: true })
      # Skipped middleware should not appear in timings
      expect(output[:timings].length).to eq(1)
      expect(output[:timings].first[:name]).to eq(:kept)
    end

    it 'handles halt during profiling' do
      stack.use(lambda { |_env, _next_mw|
        raise Philiprehberger::Middleware::Halt
      }, name: :halter)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :after)

      output = stack.profile({ data: true })
      expect(output[:result]).to eq({ data: true })
    end
  end

  describe '#merge' do
    it 'combines two stacks' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :a)

      other = described_class.new
      other.use(->(env, next_mw) { next_mw.call(env) }, name: :b)
      other.use(->(env, next_mw) { next_mw.call(env) }, name: :c)

      stack.merge(other)
      expect(stack.to_a).to eq(%i[a b c])
    end

    it 'executes merged middleware in correct order' do
      stack.use(->(env, next_mw) { next_mw.call(env + [1]) }, name: :first)

      other = described_class.new
      other.use(->(env, next_mw) { next_mw.call(env + [2]) }, name: :second)

      stack.merge(other)
      expect(stack.call([])).to eq([1, 2])
    end

    it 'does not modify the source stack' do
      other = described_class.new
      other.use(->(env, next_mw) { next_mw.call(env) }, name: :from_other)

      stack.merge(other)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :extra)

      expect(other.to_a).to eq([:from_other])
    end

    it 'returns self for chaining' do
      other = described_class.new
      expect(stack.merge(other)).to eq(stack)
    end

    it 'raises if argument is not a Stack' do
      expect { stack.merge([]) }
        .to raise_error(Philiprehberger::Middleware::Error, /must be a Stack/)
    end

    it 'merges an empty stack without issues' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :a)
      stack.merge(described_class.new)
      expect(stack.to_a).to eq([:a])
    end

    it 'preserves guards from merged stack' do
      other = described_class.new
      other.use(
        ->(env, next_mw) { next_mw.call(env.merge(guarded: true)) },
        name: :guarded,
        if: -> { false }
      )

      stack.merge(other)
      result = stack.call({})
      expect(result).to eq({})
    end
  end

  describe '#replace' do
    it 'replaces a named middleware' do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(original: true)) }, name: :target)
      stack.replace(:target, ->(env, next_mw) { next_mw.call(env.merge(replaced: true)) })

      result = stack.call({})
      expect(result).to eq({ replaced: true })
    end

    it 'preserves the name by default' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      stack.replace(:target, ->(env, next_mw) { next_mw.call(env) })
      expect(stack.to_a).to eq([:target])
    end

    it 'allows overriding the name' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :old_name)
      stack.replace(:old_name, ->(env, next_mw) { next_mw.call(env) }, name: :new_name)
      expect(stack.to_a).to eq([:new_name])
    end

    it 'preserves position in the stack' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :second)
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :third)

      stack.replace(:second, ->(env, next_mw) { next_mw.call(env) }, name: :replaced)
      expect(stack.to_a).to eq(%i[first replaced third])
    end

    it 'raises if target not found' do
      expect { stack.replace(:missing, ->(e, n) { n.call(e) }) }
        .to raise_error(Philiprehberger::Middleware::Error, /not found/)
    end

    it 'raises if new middleware is not callable' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      expect { stack.replace(:target, 'not callable') }
        .to raise_error(Philiprehberger::Middleware::Error, /call/)
    end

    it 'returns self for chaining' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      result = stack.replace(:target, ->(env, next_mw) { next_mw.call(env) })
      expect(result).to eq(stack)
    end

    it 'preserves existing guards from the replaced entry' do
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(ran: true)) },
        name: :guarded,
        if: -> { false }
      )
      stack.replace(:guarded, ->(env, next_mw) { next_mw.call(env.merge(replaced: true)) })

      result = stack.call({})
      expect(result).to eq({})
    end
  end

  describe '#[]' do
    it 'returns middleware by name' do
      mw = ->(env, next_mw) { next_mw.call(env) }
      stack.use(mw, name: :target)
      expect(stack[:target]).to eq(mw)
    end

    it 'returns nil when name not found' do
      expect(stack[:missing]).to be_nil
    end

    it 'returns the correct middleware among multiple entries' do
      mw1 = ->(env, next_mw) { next_mw.call(env) }
      mw2 = ->(env, next_mw) { next_mw.call(env) }
      stack.use(mw1, name: :first)
      stack.use(mw2, name: :second)

      expect(stack[:first]).to eq(mw1)
      expect(stack[:second]).to eq(mw2)
    end
  end

  # --- Middleware Groups ---

  describe 'middleware groups' do
    before do
      stack.use(->(env, next_mw) { next_mw.call(env.merge(verify_token: true)) }, name: :verify_token)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(load_user: true)) }, name: :load_user)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(check_permissions: true)) }, name: :check_permissions)
      stack.use(->(env, next_mw) { next_mw.call(env.merge(logging: true)) }, name: :logging)
      stack.group(:auth, %i[verify_token load_user check_permissions])
    end

    describe '#group' do
      it 'defines a named group of middleware' do
        expect(stack.group_enabled?(:auth)).to be true
      end

      it 'returns self for chaining' do
        result = stack.group(:other, [:logging])
        expect(result).to eq(stack)
      end
    end

    describe '#disable_group' do
      it 'disables a group so its middleware are skipped during call' do
        stack.disable_group(:auth)
        result = stack.call({})
        expect(result).to eq({ logging: true })
      end

      it 'returns self for chaining' do
        result = stack.disable_group(:auth)
        expect(result).to eq(stack)
      end
    end

    describe '#enable_group' do
      it 're-enables a previously disabled group' do
        stack.disable_group(:auth)
        stack.enable_group(:auth)
        result = stack.call({})
        expect(result).to eq({ verify_token: true, load_user: true, check_permissions: true, logging: true })
      end

      it 'returns self for chaining' do
        result = stack.enable_group(:auth)
        expect(result).to eq(stack)
      end
    end

    describe '#group_enabled?' do
      it 'returns true when group is enabled' do
        expect(stack.group_enabled?(:auth)).to be true
      end

      it 'returns false when group is disabled' do
        stack.disable_group(:auth)
        expect(stack.group_enabled?(:auth)).to be false
      end

      it 'returns true for undefined groups' do
        expect(stack.group_enabled?(:nonexistent)).to be true
      end
    end

    it 'allows toggling groups on and off between calls' do
      result1 = stack.call({})
      expect(result1).to include(verify_token: true)

      stack.disable_group(:auth)
      result2 = stack.call({})
      expect(result2).not_to include(:verify_token)
      expect(result2).to include(logging: true)

      stack.enable_group(:auth)
      result3 = stack.call({})
      expect(result3).to include(verify_token: true)
    end

    it 'supports multiple groups' do
      stack.group(:logging_group, [:logging])
      stack.disable_group(:auth)
      stack.disable_group(:logging_group)

      result = stack.call({})
      expect(result).to eq({})
    end

    it 'only disables middleware in the disabled group' do
      stack.disable_group(:auth)
      result = stack.call({})
      expect(result).to eq({ logging: true })
      expect(result).not_to include(:verify_token)
    end

    it 'works with profiling when groups are disabled' do
      stack.disable_group(:auth)
      output = stack.profile({})
      expect(output[:result]).to eq({ logging: true })
      expect(output[:timings].map { |t| t[:name] }).to eq([:logging])
    end
  end

  # --- Before/After Hooks ---

  describe 'before/after hooks' do
    describe '#before' do
      it 'runs a hook before the named middleware' do
        order = []
        stack.use(lambda { |env, next_mw|
          order << :middleware
          next_mw.call(env)
        }, name: :logging)
        stack.before(:logging) { |_env| order << :before_hook }

        stack.call({})
        expect(order).to eq(%i[before_hook middleware])
      end

      it 'allows multiple before hooks on the same middleware' do
        order = []
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        stack.before(:logging) { |_env| order << :hook1 }
        stack.before(:logging) { |_env| order << :hook2 }

        stack.call({})
        expect(order).to eq(%i[hook1 hook2])
      end

      it 'passes the env to the hook' do
        captured_env = nil
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        stack.before(:logging) { |env| captured_env = env }

        stack.call({ request_id: 123 })
        expect(captured_env).to eq({ request_id: 123 })
      end

      it 'returns self for chaining' do
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        result = stack.before(:logging) { |_env| nil }
        expect(result).to eq(stack)
      end

      it 'allows hooks to modify the env hash in place' do
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        stack.before(:logging) { |env| env[:start] = Time.now }

        result = stack.call({})
        expect(result).to have_key(:start)
        expect(result[:start]).to be_a(Time)
      end
    end

    describe '#after' do
      it 'runs a hook after the named middleware' do
        order = []
        stack.use(lambda { |env, next_mw|
          order << :middleware
          next_mw.call(env)
        }, name: :logging)
        stack.after(:logging) { |_env| order << :after_hook }

        stack.call({})
        expect(order).to eq(%i[middleware after_hook])
      end

      it 'allows multiple after hooks on the same middleware' do
        order = []
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        stack.after(:logging) { |_env| order << :hook1 }
        stack.after(:logging) { |_env| order << :hook2 }

        stack.call({})
        expect(order).to eq(%i[hook1 hook2])
      end

      it 'passes the env to the hook' do
        captured_env = nil
        stack.use(lambda { |env, next_mw|
  env[:processed] = true
  next_mw.call(env)
}, name: :logging)
        stack.after(:logging) { |env| captured_env = env }

        stack.call({})
        expect(captured_env).to include(:processed)
      end

      it 'returns self for chaining' do
        stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)
        result = stack.after(:logging) { |_env| nil }
        expect(result).to eq(stack)
      end
    end

    describe 'before and after combined' do
      it 'runs before hooks, then middleware, then after hooks' do
        order = []
        stack.use(lambda { |env, next_mw|
          order << :middleware
          next_mw.call(env)
        }, name: :process)
        stack.before(:process) { |_env| order << :before }
        stack.after(:process) { |_env| order << :after }

        stack.call({})
        expect(order).to eq(%i[before middleware after])
      end

      it 'hooks do not affect the return value of the chain' do
        stack.use(->(env, next_mw) { next_mw.call(env.merge(data: true)) }, name: :process)
        stack.before(:process) { |_env| :ignored_before }
        stack.after(:process) { |_env| :ignored_after }

        result = stack.call({})
        expect(result).to eq({ data: true })
      end
    end

    it 'does not run hooks for skipped conditional middleware' do
      hook_called = false
      stack.use(
        ->(env, next_mw) { next_mw.call(env) },
        name: :guarded,
        if: -> { false }
      )
      stack.before(:guarded) { |_env| hook_called = true }

      stack.call({})
      expect(hook_called).to be false
    end

    it 'does not run hooks for disabled group middleware' do
      hook_called = false
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :auth_check)
      stack.group(:auth, [:auth_check])
      stack.before(:auth_check) { |_env| hook_called = true }
      stack.disable_group(:auth)

      stack.call({})
      expect(hook_called).to be false
    end
  end

  # --- Timeout Per Middleware ---

  describe 'timeout per middleware' do
    it 'executes middleware normally when within timeout' do
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(done: true)) },
        name: :fast,
        timeout: 5
      )

      result = stack.call({})
      expect(result).to eq({ done: true })
    end

    it 'raises TimeoutError when middleware exceeds timeout' do
      stack.use(
        lambda { |_env, _next_mw|
          sleep(2)
        },
        name: :slow_api,
        timeout: 0.1
      )

      expect { stack.call({}) }
        .to raise_error(Philiprehberger::Middleware::TimeoutError, /slow_api/)
    end

    it 'includes middleware name in the error message' do
      stack.use(
        lambda { |_env, _next_mw|
          sleep(2)
        },
        name: :external_api,
        timeout: 0.1
      )

      expect { stack.call({}) }
        .to raise_error(Philiprehberger::Middleware::TimeoutError, /external_api/)
    end

    it 'includes the timeout duration in the error message' do
      stack.use(
        lambda { |_env, _next_mw|
          sleep(2)
        },
        name: :slow,
        timeout: 0.1
      )

      expect { stack.call({}) }
        .to raise_error(Philiprehberger::Middleware::TimeoutError, /0\.1s timeout/)
    end

    it 'does not restrict middleware without timeout' do
      stack.use(
        lambda { |env, next_mw|
          sleep(0.05)
          next_mw.call(env.merge(done: true))
        },
        name: :no_timeout
      )

      result = stack.call({})
      expect(result).to eq({ done: true })
    end

    it 'allows mixing middleware with and without timeouts' do
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(first: true)) },
        name: :first,
        timeout: 5
      )
      stack.use(
        ->(env, next_mw) { next_mw.call(env.merge(second: true)) },
        name: :second
      )

      result = stack.call({})
      expect(result).to eq({ first: true, second: true })
    end

    it 'TimeoutError is not caught by on_error' do
      stack.use(
        lambda { |_env, _next_mw|
          sleep(2)
        },
        name: :slow,
        timeout: 0.1,
        on_error: ->(_e, _env) {}
      )

      expect { stack.call({}) }
        .to raise_error(Philiprehberger::Middleware::TimeoutError)
    end

    it 'works with insert_before timeout option' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      stack.insert_before(
        :target,
        ->(env, next_mw) { next_mw.call(env.merge(inserted: true)) },
        name: :fast_insert,
        timeout: 5
      )

      result = stack.call({})
      expect(result).to eq({ inserted: true })
    end

    it 'works with insert_after timeout option' do
      stack.use(->(env, next_mw) { next_mw.call(env) }, name: :target)
      stack.insert_after(
        :target,
        ->(env, next_mw) { next_mw.call(env.merge(inserted: true)) },
        name: :fast_insert,
        timeout: 5
      )

      result = stack.call({})
      expect(result).to eq({ inserted: true })
    end

    it 'preserves timeout on replace' do
      stack.use(
        lambda { |_env, _next_mw|
          sleep(2)
        },
        name: :slow,
        timeout: 0.1
      )
      stack.replace(:slow, lambda { |_env, _next_mw|
        sleep(2)
      })

      expect { stack.call({}) }
        .to raise_error(Philiprehberger::Middleware::TimeoutError)
    end
  end
end
