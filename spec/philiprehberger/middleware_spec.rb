# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Philiprehberger::Middleware do
  describe 'VERSION' do
    it 'has a version number' do
      expect(Philiprehberger::Middleware::VERSION).not_to be_nil
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
end
