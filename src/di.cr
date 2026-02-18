module Di
  # Module-level registry storing all providers.
  # This is the root scope container.
  @@registry = Registry.new

  # Returns the root registry (for internal use).
  def self.registry : Registry
    @@registry
  end

  # Auto-wire a service by type (no block).
  #
  # Inspects the type's `initialize` method arguments at compile time and
  # resolves each from the container. All arguments must have type restrictions.
  #
  # Example:
  # ```
  # Di.provide UserService
  # Di.provide UserService, transient: true
  # Di.provide UserService, as: :primary
  # ```
  macro provide(type, *, as _name = nil, transient _transient = false)
    {% init_method = type.resolve.methods.find { |method| method.name == "initialize" } %}
    {% if init_method %}
      {% for arg in init_method.args %}
        {% if arg.restriction.nil? %}
          {% raise "Di.provide auto-wire requires type restriction on argument '#{arg.name}' in #{type}#initialize" %}
        {% end %}
      {% end %}
      %factory = -> {
        {{ type }}.new(
          {% for arg in init_method.args %}
            {{ arg.name }}: Di.invoke({{ arg.restriction }}),
          {% end %}
        )
      }
    {% else %}
      %factory = -> { {{ type }}.new }
    {% end %}
    {% if _name %}
      %key = Di::Registry.key({{ type }}.name, {{ _name.id.stringify }})
    {% else %}
      %key = {{ type }}.name
    {% end %}
    Di.registry.register(%key, Di::Provider::Instance({{ type }}).new(%factory, transient: {{ _transient }}))
  end

  # Register a service provider with a factory block.
  #
  # The block's return type is inferred at compile time via typeof.
  # The provider stores the factory and manages singleton caching by default.
  #
  # Example:
  # ```
  # Di.provide { Database.new(ENV["DATABASE_URL"]) }
  # Di.provide(as: :primary) { Database.new(ENV["PRIMARY_URL"]) }
  # ```
  #
  # Raises `Di::AlreadyRegistered` if the type+name pair is already registered.
  macro provide(*, as _name = nil, transient _transient = false, &block)
    %factory = -> { {{ block.body }} }
    {% if _name %}
      %key = Di::Registry.key(typeof({{ block.body }}).name, {{ _name.id.stringify }})
    {% else %}
      %key = typeof({{ block.body }}).name
    {% end %}
    Di.registry.register(%key, Di::Provider::Instance(typeof({{ block.body }})).new(%factory, transient: {{ _transient }}))
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
  # primary = Di.invoke(Database, :primary)
  # ```
  #
  # Raises `Di::ServiceNotFound` if the type is not registered.
  macro invoke(type, name = nil)
    {% if name %}
      Di.registry.get(Di::Registry.key({{ type }}.name, {{ name.id.stringify }})).as(Di::Provider::Instance({{ type }})).resolve_typed
    {% else %}
      Di.registry.get({{ type }}.name).as(Di::Provider::Instance({{ type }})).resolve_typed
    {% end %}
  end

  # Resolve a service by type, returning nil if not registered.
  #
  # Returns `T?` — the instance or nil. Does not raise.
  #
  # Example:
  # ```
  # db = Di.invoke?(Database)
  # replica = Di.invoke?(Database, :replica)
  # ```
  macro invoke?(type, name = nil)
    {% if name %}
      %provider = Di.registry.get?(Di::Registry.key({{ type }}.name, {{ name.id.stringify }}))
    {% else %}
      %provider = Di.registry.get?({{ type }}.name)
    {% end %}
    if %provider
      %provider.as(Di::Provider::Instance({{ type }})).resolve_typed
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
