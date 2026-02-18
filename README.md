# di

[![Crystal Version](https://img.shields.io/badge/Crystal-%3E%3D1.19.1-000000?style=flat&labelColor=24292e&color=000000&logo=crystal&logoColor=white)](https://crystal-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat&labelColor=24292e&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![Docs](https://img.shields.io/badge/Docs-API%20Reference-5e5086?style=flat&labelColor=24292e&logo=gitbook&logoColor=white)](https://crystaldoc.info/github/omarluq/di)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-28a745?style=flat&labelColor=24292e&logo=checkmarx&logoColor=white)](https://github.com/omarluq/di)
[![codecov](https://img.shields.io/codecov/c/github/omarluq/di?style=flat&labelColor=24292e&logo=codecov&logoColor=white)](https://codecov.io/gh/omarluq/di)
[![Made with Love](https://img.shields.io/badge/Made%20with-Love-ff69b4?style=flat&labelColor=24292e&logo=githubsponsors&logoColor=white)](https://github.com/omarluq/di)

A type-safe, macro-first dependency injection shard for Crystal. Inspired by [`samber/do`](https://github.com/samber/do) v2 for Go.

Zero dependencies. Zero boilerplate. One macro to register, one macro to resolve. Fully type-safe at compile time.

## How It Works

`di` uses Crystal's compile-time macros to build a fully typed DI container with no runtime reflection.

**Registration** is done via `Di.provide`. When given a bare type, the macro inspects its `initialize` method at compile time, discovers each dependency's type, and emits `Di.invoke(DependencyType)` calls to auto-wire the constructor. When given a block, the return type is inferred via `typeof`. Either way, a typed `Provider::Instance(T)` is stored in an internal registry keyed by type name.

**Resolution** is done via `Di.invoke(T)`. The macro expands to a registry lookup and a cast to `Provider::Instance(T)`, so the return type is always exactly `T`. Singletons are cached on first resolve; transient providers call the factory every time.

**Scopes** create isolated child containers that inherit from their parent (or root). Providers registered inside a scope block are local to that scope. On block exit, scope-local singletons are shut down automatically. Scope state is fiber-local, so concurrent requests get full isolation.

**Lifecycle hooks** are duck-typed. If a service responds to `shutdown`, it participates in graceful shutdown. If it responds to `healthy?`, it participates in health reporting. No interfaces or module inclusion required.

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
