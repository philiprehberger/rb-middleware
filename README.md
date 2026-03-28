# philiprehberger-middleware

[![Tests](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml) [![Gem Version](https://img.shields.io/gem/v/philiprehberger-middleware)](https://rubygems.org/gems/philiprehberger-middleware) [![GitHub release](https://img.shields.io/github/v/release/philiprehberger/rb-middleware)](https://github.com/philiprehberger/rb-middleware/releases) [![GitHub last commit](https://img.shields.io/github/last-commit/philiprehberger/rb-middleware)](https://github.com/philiprehberger/rb-middleware/commits/main) [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) [![Bug Reports](https://img.shields.io/badge/bug-reports-red.svg)](https://github.com/philiprehberger/rb-middleware/issues) [![Feature Requests](https://img.shields.io/badge/feature-requests-blue.svg)](https://github.com/philiprehberger/rb-middleware/issues) [![GitHub Sponsors](https://img.shields.io/badge/sponsor-philiprehberger-ea4aaa.svg?logo=github)](https://github.com/sponsors/philiprehberger)

Generic middleware stack for composing processing pipelines with conditional execution, error handling, profiling, and stack composition.

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

### Basic Stack

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

### Insert, Remove, and Replace

```ruby
stack = Philiprehberger::Middleware::Stack.new
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :first)
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :last)

stack.insert_before(:last, ->(env, next_mw) { next_mw.call(env) }, name: :middle)
stack.to_a  # => [:first, :middle, :last]

stack.remove(:middle)
stack.to_a  # => [:first, :last]

stack.replace(:first, ->(env, next_mw) { next_mw.call(env.merge(replaced: true)) })
```

### Named Middleware Lookup

```ruby
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :auth)

middleware = stack[:auth]  # => returns the middleware callable
stack[:missing]            # => nil
```

### Conditional Middleware

```ruby
stack.use(
  ->(env, next_mw) { next_mw.call(env.merge(debug: true)) },
  name: :debug,
  if: -> { ENV["DEBUG"] == "true" }
)

stack.use(
  ->(env, next_mw) { next_mw.call(env.merge(cached: true)) },
  name: :cache,
  unless: -> { ENV["NO_CACHE"] }
)
```

### Error Handling

```ruby
stack.use(
  ->(env, next_mw) { next_mw.call(env) },
  name: :risky,
  on_error: ->(error, env) { puts "Error: #{error.message}" }
)
```

When `on_error` is set, the handler is called and the chain continues with the next middleware. Without `on_error`, exceptions propagate normally.

### Halt Mechanism

Stop the middleware chain early by setting `env[:halt] = true` or raising `Halt`:

```ruby
# Using env[:halt]
stack.use(lambda { |env, next_mw|
  return env.merge(halt: true, reason: "unauthorized") unless env[:token]

  next_mw.call(env)
}, name: :auth)

# Using Halt exception
stack.use(lambda { |env, _next_mw|
  raise Philiprehberger::Middleware::Halt unless env[:token]

  _next_mw.call(env)
}, name: :auth)
```

### Profiling

```ruby
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :auth)
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logger)

output = stack.profile({})
# output[:result]  => the final env
# output[:timings] => [{ name: :auth, duration: 0.00012 }, { name: :logger, duration: 0.00005 }]
```

### Stack Composition

```ruby
auth_stack = Philiprehberger::Middleware::Stack.new
auth_stack.use(->(env, next_mw) { next_mw.call(env) }, name: :auth)

logging_stack = Philiprehberger::Middleware::Stack.new
logging_stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logger)

auth_stack.merge(logging_stack)
auth_stack.to_a  # => [:auth, :logger]
```

## API

### `Stack`

| Method | Description |
|--------|-------------|
| `.new` | Create an empty middleware stack |
| `#use(mw, name:, if:, unless:, on_error:)` | Append middleware with optional guards and error handler |
| `#insert_before(name, mw, name:, if:, unless:, on_error:)` | Insert middleware before a named entry |
| `#insert_after(name, mw, name:, if:, unless:, on_error:)` | Insert middleware after a named entry |
| `#remove(name)` | Remove middleware by name |
| `#replace(name, mw, name:)` | Replace a named middleware, preserving position and guards |
| `#[](name)` | Look up middleware by name, returns nil if not found |
| `#call(env)` | Execute the stack with the given environment |
| `#profile(env)` | Execute the stack and return `{ result:, timings: }` with per-middleware durations |
| `#merge(other_stack)` | Append all entries from another stack |
| `#to_a` | List middleware names in order |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Philip%20Rehberger-blue?logo=linkedin)](https://linkedin.com/in/philiprehberger) [![More Packages](https://img.shields.io/badge/more-packages-blue.svg)](https://github.com/philiprehberger?tab=repositories)

## License

MIT
