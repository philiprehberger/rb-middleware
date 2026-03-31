# philiprehberger-middleware

[![Tests](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-middleware/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-middleware.svg)](https://rubygems.org/gems/philiprehberger-middleware)
[![GitHub release](https://img.shields.io/github/v/release/philiprehberger/rb-middleware)](https://github.com/philiprehberger/rb-middleware/releases)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-middleware)](https://github.com/philiprehberger/rb-middleware/commits/main)
[![License](https://img.shields.io/github/license/philiprehberger/rb-middleware)](LICENSE)
[![Bug Reports](https://img.shields.io/github/issues/philiprehberger/rb-middleware/bug)](https://github.com/philiprehberger/rb-middleware/issues?q=is%3Aissue+is%3Aopen+label%3Abug)
[![Feature Requests](https://img.shields.io/github/issues/philiprehberger/rb-middleware/enhancement)](https://github.com/philiprehberger/rb-middleware/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)
[![Sponsor](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ec6cb9)](https://github.com/sponsors/philiprehberger)

Generic middleware stack for composing processing pipelines with conditional execution, error handling, profiling, and stack composition

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

### Middleware Groups

```ruby
stack = Philiprehberger::Middleware::Stack.new
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :verify_token)
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :load_user)
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :check_permissions)

stack.group(:auth, [:verify_token, :load_user, :check_permissions])
stack.disable_group(:auth)   # skips all auth middleware during call
stack.group_enabled?(:auth)  # => false
stack.enable_group(:auth)    # re-enables the group
```

### Before/After Hooks

```ruby
stack.use(->(env, next_mw) { next_mw.call(env) }, name: :logging)

stack.before(:logging) { |env| env[:start] = Time.now }
stack.after(:logging) { |env| puts "Duration: #{Time.now - env[:start]}s" }
```

### Timeout Per Middleware

```ruby
stack.use(
  ->(env, next_mw) { next_mw.call(env) },
  name: :external_api,
  timeout: 5
)
# Raises Philiprehberger::Middleware::TimeoutError if middleware exceeds 5 seconds
```

### Error Handling

```ruby
stack.use(
  ->(env, next_mw) { next_mw.call(env) },
  name: :risky,
  on_error: ->(error, env) { puts "Error: #{error.message}" }
)
```

### Halt Mechanism

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
| `#use(mw, name:, if:, unless:, on_error:, timeout:)` | Append middleware with optional guards, error handler, and timeout |
| `#insert_before(name, mw, name:, if:, unless:, on_error:, timeout:)` | Insert middleware before a named entry |
| `#insert_after(name, mw, name:, if:, unless:, on_error:, timeout:)` | Insert middleware after a named entry |
| `#remove(name)` | Remove middleware by name |
| `#replace(name, mw, name:)` | Replace a named middleware, preserving position and guards |
| `#[](name)` | Look up middleware by name, returns nil if not found |
| `#call(env)` | Execute the stack with the given environment |
| `#profile(env)` | Execute the stack and return `{ result:, timings: }` with per-middleware durations |
| `#merge(other_stack)` | Append all entries from another stack |
| `#to_a` | List middleware names in order |
| `#group(name, middleware_names)` | Define a named group of middleware |
| `#enable_group(name)` | Enable a previously disabled middleware group |
| `#disable_group(name)` | Disable a middleware group so its entries are skipped |
| `#group_enabled?(name)` | Check if a middleware group is enabled |
| `#before(name, &block)` | Attach a hook that runs before the named middleware |
| `#after(name, &block)` | Attach a hook that runs after the named middleware |
| `#clear` | Remove all middleware entries, groups, and hooks |
| `#swap(name1, name2)` | Swap positions of two named entries |
| `#stats` | Return metadata hash with count, named, groups, and hooks |
| `#describe` | Return a human-readable stack summary |
| `#frozen_copy` | Return an immutable snapshot that can execute but not be modified |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this package useful, consider giving it a star on GitHub — it helps motivate continued maintenance and development.

[![LinkedIn](https://img.shields.io/badge/Philip%20Rehberger-LinkedIn-0A66C2?logo=linkedin)](https://www.linkedin.com/in/philiprehberger)
[![More packages](https://img.shields.io/badge/more-open%20source%20packages-blue)](https://philiprehberger.com/open-source-packages)

## License

[MIT](LICENSE)
