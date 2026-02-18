# di

A type-safe, macro-first dependency injection shard for Crystal. Inspired by [`samber/do`](https://github.com/samber/do) v2 for Go.

Zero dependencies. Zero boilerplate. One macro to register, one macro to resolve. Fully type-safe at compile time.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  di:
    github: omarluq/di
```

## Usage

```crystal
require "di"
```

### Basic Registration

```crystal
# Explicit block, type inferred from return value
Di.provide { Database.new(ENV["DATABASE_URL"]) }
Di.provide { HttpClient.new(timeout: 30) }

# Auto-wire, bare type, constructor deps resolved automatically
Di.provide UserService
Di.provide UserRepository
```

### Resolution

```crystal
# Returns exactly UserService, fully typed, no casting
svc = Di.invoke(UserService)

# Nilable version, returns nil if not registered
db = Di.invoke?(Database)
```

### Named Providers

```crystal
# Multiple instances of the same type
Di.provide(as: :primary) { Database.new(ENV["PRIMARY_URL"]) }
Di.provide(as: :replica) { Database.new(ENV["REPLICA_URL"]) }

primary = Di.invoke(Database, :primary)
replica = Di.invoke(Database, :replica)
```

### Transient

```crystal
# New instance on every invoke
Di.provide UserService, transient: true
Di.provide(as: :replica, transient: true) { Database.new(url) }
```

### Scopes

```crystal
Di.scope(:request) do
  Di.provide { CurrentUser.from_token(token) }

  # Inherits from root
  user = Di.invoke(CurrentUser)
  svc  = Di.invoke(UserService)
end
# Scope auto-shuts down here
```

### Health Check

```crystal
# Returns Hash(String, Bool) for all resolved singletons that implement healthy?
health = Di.healthy?

# For a named scope
health = Di.healthy?(:request)
```

### Shutdown

```crystal
# Calls shutdown on all singletons that implement it, reverse registration order
Di.shutdown!
```

## Development

```bash
crystal spec
./bin/ameba
crystal tool format --check
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT
