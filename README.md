# philiprehberger-middleware

[![Tests](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-middleware.svg)](https://rubygems.org/gems/philiprehberger-middleware)
[![License](https://img.shields.io/github/license/philiprehberger/rb-middleware)](LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ec6cb9)](https://github.com/sponsors/philiprehberger)

Generic middleware stack for composing processing pipelines

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-middleware"
```

Or install directly:

```bash
gem install philiprehberger-middleware
```

## Usage

```ruby
require "philiprehberger/middleware"

stack = Philiprehberger::Middleware::Stack.new
stack.use(->(env, next_mw) { next_mw.call(env.merge(logged: true)) }, name: :logger)
stack.use(->(env, next_mw) { next_mw.call(env.merge(authed: true)) }, name: :auth)

result = stack.call({})
# => { logged: true, authed: true }
```

### Class-Based Middleware

```ruby
class TimingMiddleware
  def call(env, next_mw)
    start = Time.now
    result = next_mw.call(env)
    result.merge(elapsed: Time.now - start)
  end
end

stack = Philiprehberger::Middleware::Stack.new
stack.use(TimingMiddleware.new, name: :timing)
```

### Insert and Remove

```ruby
stack = Philiprehberger::Middleware::Stack.new
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :last)

stack.insert_before(:last, ->(env, next_mw) { next_mw.call(env) }, name: :middle)
stack.to_a  # => [:first, :middle, :last]

stack.remove(:middle)
stack.to_a  # => [:first, :last]
```

### Short-Circuit

```ruby
stack = Philiprehberger::Middleware::Stack.new
stack.use(lambda { |env, _next_mw|
  return { error: 'unauthorized' } unless env[:token]

  _next_mw.call(env)
}, name: :auth)
```

## API

### `Stack`

| Method | Description |
|--------|-------------|
| `.new` | Create an empty middleware stack |
| `#use(mw, name:)` | Append middleware to the stack |
| `#insert_before(name, mw, name:)` | Insert middleware before a named entry |
| `#insert_after(name, mw, name:)` | Insert middleware after a named entry |
| `#remove(name)` | Remove middleware by name |
| `#call(env)` | Execute the stack with the given environment |
| `#to_a` | List middleware names in order |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT
