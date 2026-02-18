module Di
  # Module-level registry storing root scope providers.
  @@registry = Registry.new

  # Active scope stack for nested scope support.
  @@scope_stack = [] of Scope

  # Named scope references for health checks.
  @@scopes = {} of Symbol => Scope

  # Returns the root registry.
  def self.registry : Registry
    @@registry
  end

  # Returns the active scope, or nil if at root level.
  def self.current_scope : Scope?
    @@scope_stack.last?
  end

  # Returns the named scope map (for health checks).
  def self.scopes : Hash(Symbol, Scope)
    @@scopes
  end

  # Register a provider in the current scope (or root registry).
  def self.register_provider(key : String, provider : Provider::Base) : Nil
    if scope = current_scope
      scope.register(key, provider)
    else
      registry.register(key, provider)
    end
  end

  # Get a provider from the current scope chain (or root registry).
  def self.get_provider(key : String) : Provider::Base
    if scope = current_scope
      scope.get(key)
    else
      registry.get(key)
    end
  end

  # Get a provider from the current scope chain, returning nil if not found.
  def self.get_provider?(key : String) : Provider::Base?
    if scope = current_scope
      scope.get?(key)
    else
      registry.get?(key)
    end
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
    Di.register_provider(%key, Di::Provider::Instance({{ type }}).new(%factory, transient: {{ _transient }}))
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
    Di.register_provider(%key, Di::Provider::Instance(typeof({{ block.body }})).new(%factory, transient: {{ _transient }}))
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
      Di.get_provider(Di::Registry.key({{ type }}.name, {{ name.id.stringify }})).as(Di::Provider::Instance({{ type }})).resolve_typed
    {% else %}
      Di.get_provider({{ type }}.name).as(Di::Provider::Instance({{ type }})).resolve_typed
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
      %provider = Di.get_provider?(Di::Registry.key({{ type }}.name, {{ name.id.stringify }}))
    {% else %}
      %provider = Di.get_provider?({{ type }}.name)
    {% end %}
    if %provider
      %provider.as(Di::Provider::Instance({{ type }})).resolve_typed
    end
  end

  # Create a named scope with parent inheritance.
  #
  # Providers registered inside the block are scoped. The scope inherits
  # all providers from the parent (or root if at top level). On block exit,
  # shutdown is called on all scope-local singleton providers.
  #
  # Example:
  # ```
  # Di.scope(:request) do
  #   Di.provide { CurrentUser.from_token(token) }
  #   user = Di.invoke(CurrentUser)
  # end
  # ```
  def self.scope(name : Symbol, &)
    parent = current_scope
    child = Scope.new(name, parent: parent || root_scope)
    @@scopes[name] = child
    @@scope_stack.push(child)
    begin
      yield
    ensure
      shutdown_scope(child)
      @@scope_stack.pop
      @@scopes.delete(name)
    end
  end

  # Shut down all singleton providers in reverse registration order.
  #
  # Calls `.shutdown` on services that respond to it. Transient services
  # and services without `.shutdown` are skipped.
  def self.shutdown! : Nil
    registry.reverse_order.each do |key|
      provider = registry.get?(key)
      next unless provider
      provider.shutdown_instance
    end
    registry.clear
  end

  # Check health of all resolved singletons in the root registry.
  #
  # Returns a hash mapping provider keys to health status.
  # Only includes services that respond to `.healthy?` and have been resolved.
  def self.healthy? : Hash(String, Bool)
    collect_health(registry)
  end

  # Check health of all resolved singletons in a named scope.
  #
  # Includes inherited services from parent scopes.
  # Raises `Di::ScopeNotFound` if the scope is not active.
  def self.healthy?(scope_name : Symbol) : Hash(String, Bool)
    scope = @@scopes[scope_name]? || raise ScopeNotFound.new(scope_name.to_s)
    collect_scope_health(scope)
  end

  # Clear all providers and scopes (test helper).
  #
  # Resets the container to a clean state. Primarily for use in specs.
  def self.reset! : Nil
    @@registry.clear
    @@scope_stack.clear
    @@scopes.clear
  end

  # Build a root scope wrapper around the registry for scope parent chains.
  private def self.root_scope : Scope
    root = Scope.new(:root)
    registry.each { |key, provider| root.register(key, provider) }
    root
  end

  # Shutdown providers in a scope.
  private def self.shutdown_scope(scope : Scope) : Nil
    scope.reverse_order.each do |key|
      provider = scope.get?(key)
      next unless provider
      provider.shutdown_instance
    end
  end

  # Collect health from registry providers.
  private def self.collect_health(reg : Registry) : Hash(String, Bool)
    result = {} of String => Bool
    reg.each do |key, provider|
      status = provider.check_health
      result[key] = status unless status.nil?
    end
    result
  end

  # Collect health from a scope, walking the parent chain.
  private def self.collect_scope_health(scope : Scope) : Hash(String, Bool)
    result = {} of String => Bool
    # Walk parents first so child overrides take precedence.
    if parent = scope.parent
      result.merge!(collect_scope_health(parent))
    end
    scope.each do |key, provider|
      status = provider.check_health
      result[key] = status unless status.nil?
    end
    result
  end
end

require "./di/*"
