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

  # Clear all providers (test helper).
  #
  # Resets the container to a clean state. Primarily for use in specs.
  def self.reset! : Nil
    @@registry.clear
  end
end

require "./di/*"
