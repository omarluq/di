module Di
  # Module-level registry storing all providers.
  # This is the root scope container.
  @@registry = Registry.new

  # Returns the root registry (for internal use).
  def self.registry : Registry
    @@registry
  end

  # Register a service provider with a factory block.
  #
  # The block's return type is inferred at compile time via typeof.
  # The provider stores the factory and manages singleton caching by default.
  #
  # Example:
  # ```
  # Di.provide { Database.new(ENV["DATABASE_URL"]) }
  # Di.provide { HttpClient.new(timeout: 30) }
  # ```
  #
  # Raises `Di::AlreadyRegistered` if the type is already registered.
  macro provide(&block)
    %factory = -> { {{ block.body }} }
    %key = typeof({{ block.body }}).name
    Di.registry.register(%key, Di::Provider(typeof({{ block.body }})).new(%factory))
  end

  # Resolve a service by type.
  #
  # Returns the instance as exactly `T` — fully typed, no casting.
  # Singleton providers return the cached instance; transient providers
  # create a new instance on every call.
  #
  # Example:
  # ```
  # db = Di.invoke(Database)
  # ```
  #
  # Raises `Di::ServiceNotFound` if the type is not registered.
  macro invoke(type)
    Di.registry.get({{ type }}.name).as(Di::Provider({{ type }})).resolve_typed
  end

  # Resolve a service by type, returning nil if not registered.
  #
  # Returns `T?` — the instance or nil. Does not raise.
  #
  # Example:
  # ```
  # db = Di.invoke?(Database) # => Database | Nil
  # ```
  macro invoke?(type)
    %provider = Di.registry.get?({{ type }}.name)
    if %provider
      %provider.as(Di::Provider({{ type }})).resolve_typed
    end
  end

  # Clear all providers (test helper).
  #
  # Resets the container to a clean state. Primarily for use in specs.
  def self.reset! : Nil
    @@registry.clear
  end
end

require "./di/*"
