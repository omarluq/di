<p align="center">
  <img src="logo2.png" alt="Logo"/>
</p>

<div align="center">

[![Crystal Version](https://img.shields.io/badge/Crystal-%3E%3D1.19.1-000000?style=flat&labelColor=24292e&color=000000&logo=crystal&logoColor=white)](https://crystal-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat&labelColor=24292e&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![Docs](https://img.shields.io/badge/Docs-API%20Reference-5e5086?style=flat&labelColor=24292e&logo=gitbook&logoColor=white)](https://crystaldoc.info/github/omarluq/di)
[![Maintained](https://img.shields.io/badge/Maintained%3F-yes-28a745?style=flat&labelColor=24292e&logo=checkmarx&logoColor=white)](https://github.com/omarluq/di)
[![codecov](https://img.shields.io/codecov/c/github/omarluq/di?style=flat&labelColor=24292e&logo=codecov&logoColor=white)](https://codecov.io/gh/omarluq/di)
[![Made with Love](https://img.shields.io/badge/Made%20with-Love-ff69b4?style=flat&labelColor=24292e&logo=githubsponsors&logoColor=white)](https://github.com/omarluq/di)

</div>

<div align="center">

A type-safe, macro-first dependency injection shard for Crystal. Inspired by [`samber/do`](https://github.com/samber/do) v2 for Go.

Zero dependencies. Zero boilerplate. One macro to register, one macro to resolve. Fully type-safe at compile time.

</div>

## How It Works

`di` uses Crystal's compile-time macros to build a fully typed DI container with no runtime reflection.

**Registration** is done via `Di.provide`. When given a bare type, the macro inspects its `initialize` method at compile time, discovers each dependency's type, and emits resolution calls to auto-wire the constructor. When given a block, the return type is inferred via `typeof`. Either way, a typed `Provider::Instance(T)` is stored in an internal registry keyed by type name.

**Resolution** is done via `Di[Type]`. The macro expands to a registry lookup and a cast to `Provider::Instance(T)`, so the return type is always exactly `T`. Singletons are cached on first resolve; transient providers call the factory every time.

**Scopes** create isolated child containers that inherit from their parent (or root). Providers registered inside a scope block are local to that scope. Top-level scopes use a live fallback to the root registry, so root providers registered later are visible unless shadowed by scope-local providers. On block exit, scope-local singletons are shut down automatically. Scope state is fiber-local, so concurrent requests get full isolation.

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
# Note: Dependencies must be registered before first invocation
Di.provide UserService
Di.provide UserRepository
```

### Factory with Dependencies

When auto-wire isn't enough (custom construction, extra config, wrapping), declare dependency types before the block:

```crystal
# Auto-wire handles standard constructors
Di.provide Service  # resolves Repo from Service#initialize(@repo : Repo)

# Use deps+block for custom factories
Di.provide(Repo) { |repo| Service.new(repo, timeout: 30) }
Di.provide(Repo, Cache) { |repo, cache| Gateway.new(repo, cache, retries: 3) }

# Named dependency (type + service name)
Di.provide({Database, :primary}) { |db| ReplicaReader.new(db) }
```

Dependencies are resolved and passed to block arguments in order. The key is inferred from the block's return type.

### Resolution

```crystal
# Returns exactly UserService, fully typed, no casting
svc = Di[UserService]

# Nilable version, returns nil if not registered
db = Di[Database]?

# Di.invoke / Di.invoke? are available as aliases
svc = Di.invoke(UserService)
db  = Di.invoke?(Database)
```

### Named Providers

```crystal
# Multiple instances of the same type
Di.provide(as: :primary) { Database.new(ENV["PRIMARY_URL"]) }
Di.provide(as: :replica) { Database.new(ENV["REPLICA_URL"]) }

primary = Di[Database, :primary]
replica = Di[Database, :replica]
```

Note: The `as:` argument must be a Symbol literal (`:primary`), not a variable.

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
  user = Di[CurrentUser]
  svc  = Di[UserService]
end
# Scope auto-shuts down here
```

Note: `Di.provide` called inside `Di.scope` always registers in that active scope.

### Health Check

```crystal
# Returns Hash(String, Bool) for all resolved singletons that implement healthy?
health = Di.healthy?

# For a named scope
health = Di.healthy?(:request)
```

`healthy?` methods may call `Di[...]` safely.

### Shutdown

```crystal
# Calls shutdown on all singletons that implement it, reverse registration order
Di.shutdown!
```

Note: Raises `Di::ScopeError` while any scopes are active.
Note: Concurrent `Di.shutdown!` calls are serialized and use an atomic snapshot plus clear of the root registry.

## Error Handling

| Error                    | When                                                     |
| ------------------------ | -------------------------------------------------------- |
| `Di::ServiceNotFound`    | Resolving a type that was never registered               |
| `Di::CircularDependency` | Circular dependency detected during resolution           |
| `Di::AlreadyRegistered`  | Registering the same type+name twice                     |
| `Di::ScopeNotFound`      | `Di.healthy?(:name)` for unknown scope                   |
| `Di::ScopeError`         | `Di.reset!` or `Di.shutdown!` while scopes are active    |
| `Di::ShutdownError`      | One or more service shutdowns failed (aggregates errors) |

Compile-time errors occur for missing type restrictions on auto-wire or non-literal symbol arguments.

## Concurrency

- Fiber-local state isolates scope and resolution-chain tracking per fiber.
- Registry, scope, and provider internals are synchronized for multi-threaded Crystal (`-Dpreview_mt`).
- `Di.reset!` and `Di.shutdown!` raise `Di::ScopeError` while any scopes are active.
- Control-plane operations (`Di.scope` entry/exit, `Di.reset!`, `Di.shutdown!`) are coordinated through a container mutex and global active-scope guard.

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
