require "mutex"

module Di
  # Module-level registry storing root scope providers.
  @@registry = Registry.new

  # Mutex protecting fiber-local state maps for multi-threaded access.
  @@fiber_state_mutex = Mutex.new

  # Control-plane mutex serializing shutdown!/reset!/scope entry.
  # Prevents concurrent shutdown calls and guards against scope-start races.
  @@control_mutex = Mutex.new

  # Global count of active scopes across all fibers.
  @@global_scope_count = 0

  # Fiber-local scope stacks for concurrent isolation.
  @@fiber_scope_stacks = {} of Fiber => Array(Scope)

  # Fiber-local named scope map for health checks (concurrent-safe).
  @@fiber_scope_maps = {} of Fiber => Hash(Symbol, Scope)

  # Fiber-local resolution chains for circular dependency detection.
  @@fiber_resolution_chains = {} of Fiber => Array(String)

  # Returns the scope stack for the current fiber.
  private def self.scope_stack : Array(Scope)
    @@fiber_state_mutex.synchronize { @@fiber_scope_stacks[Fiber.current] ||= [] of Scope }
  end

  # Returns the named scope map for the current fiber.
  private def self.scope_map : Hash(Symbol, Scope)
    @@fiber_state_mutex.synchronize { @@fiber_scope_maps[Fiber.current] ||= {} of Symbol => Scope }
  end

  # Returns the resolution chain for the current fiber.
  private def self.resolution_chain : Array(String)
    @@fiber_state_mutex.synchronize { @@fiber_resolution_chains[Fiber.current] ||= [] of String }
  end

  # Track resolution chain to detect circular dependencies at runtime.
  # Yields to block. Raises CircularDependency if type is already in chain.
  def self.push_resolution(type_name : String, &)
    chain = resolution_chain
    if chain.includes?(type_name)
      raise CircularDependency.new(chain + [type_name])
    end
    chain << type_name
    begin
      yield
    ensure
      chain.pop
      if chain.empty?
        @@fiber_state_mutex.synchronize { @@fiber_resolution_chains.delete(Fiber.current) }
      end
    end
  end

  # :nodoc: Internal API for testing/debugging.
  def self.registry : Registry
    @@registry
  end

  # :nodoc: Internal API for testing/debugging.
  def self.current_scope : Scope?
    @@fiber_state_mutex.synchronize { @@fiber_scope_stacks[Fiber.current]?.try(&.last?) }
  end

  # :nodoc: Internal API for testing/debugging.
  def self.scopes : Hash(Symbol, Scope)
    @@fiber_state_mutex.synchronize { @@fiber_scope_maps[Fiber.current]? } || {} of Symbol => Scope
  end

  # Returns true if any fiber has an active scope.
  private def self.global_scope_active? : Bool
    @@fiber_state_mutex.synchronize { @@global_scope_count > 0 }
  end

  # Register a provider in the current scope (or root registry).
  # Sets the provider key for cycle detection before storing.
  def self.register_provider(key : String, provider : Provider::Base) : Nil
    provider.key = key
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

  # :nodoc: Internal API. Use `Di.provide(Dep) { |dep| ... }` instead.
  def self.get(type : T.class) : T forall T
    get_provider(T.name).as(Provider::Instance(T)).resolve_typed
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
      {% unless name.is_a?(SymbolLiteral) %}
        {% raise "Di.invoke name requires a Symbol literal, got #{name} (use :name not a variable)" %}
      {% end %}
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
      {% unless name.is_a?(SymbolLiteral) %}
        {% raise "Di.invoke? name requires a Symbol literal, got #{name} (use :name not a variable)" %}
      {% end %}
      %provider = Di.get_provider?(Di::Registry.key({{ type }}.name, {{ name.id.stringify }}))
    {% else %}
      %provider = Di.get_provider?({{ type }}.name)
    {% end %}
    if %provider
      %provider.as(Di::Provider::Instance({{ type }})).resolve_typed
    end
  end

  # Register a service provider.
  #
  # No block (auto-wire):
  # - `Di.provide UserService`
  # - `Di.provide UserService, as: :primary`
  #
  # Block forms:
  # - `Di.provide { Database.new(url) }`
  # - `Di.provide(A) { |a| B.new(a) }`
  # - `Di.provide(A, B) { |a, b| C.new(a, b) }`
  # - `Di.provide({Database, :primary}) { |db| Repo.new(db) }`
  #
  # With dependency types, each is resolved and passed to block arguments in order.
  # This works at top-level without macro-order issues.
  macro provide(*deps, as _name = nil, transient _transient = false, &block)
    {% if block.is_a?(Nop) %}
      {% if deps.size != 1 %}
        {% raise "Di.provide auto-wire requires exactly 1 type argument when no block is given, got #{deps.size}" %}
      {% end %}
      {% type = deps[0] %}
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
        {% unless _name.is_a?(SymbolLiteral) %}
          {% raise "Di.provide 'as:' requires a Symbol literal, got #{_name} (use :name not a variable)" %}
        {% end %}
        %key = Di::Registry.key({{ type }}.name, {{ _name.id.stringify }})
      {% else %}
        %key = {{ type }}.name
      {% end %}
      Di.register_provider(%key, Di::Provider::Instance({{ type }}).new(%factory, transient: {{ _transient }}))
    {% else %}
      {% if deps.empty? && block.args.size > 0 %}
        {% raise "Di.provide block arguments require dependency types: Di.provide(Type1, ...) { |...| ... }" %}
      {% end %}
      {% if !deps.empty? && block.args.size != deps.size %}
        {% raise "Di.provide block expects #{deps.size} argument(s) for #{deps.size} dependency type(s), got #{block.args.size}" %}
      {% end %}
      {% if deps.empty? %}
        %factory = -> { {{ block.body }} }
        {% if _name %}
          {% unless _name.is_a?(SymbolLiteral) %}
            {% raise "Di.provide 'as:' requires a Symbol literal, got #{_name} (use :name not a variable)" %}
          {% end %}
          %key = Di::Registry.key(typeof({{ block.body }}).name, {{ _name.id.stringify }})
        {% else %}
          %key = typeof({{ block.body }}).name
        {% end %}
        Di.register_provider(%key, Di::Provider::Instance(typeof({{ block.body }})).new(%factory, transient: {{ _transient }}))
      {% else %}
        {% for dep in deps %}
          {% if dep.is_a?(TupleLiteral) %}
            {% if dep.size != 2 %}
              {% raise "Di.provide named dependency must use {Type, :name}, got #{dep}" %}
            {% end %}
            {% unless dep[1].is_a?(SymbolLiteral) %}
              {% raise "Di.provide dependency name requires a Symbol literal in {Type, :name}, got #{dep[1]}" %}
            {% end %}
          {% end %}
        {% end %}
        %injector = -> (
          {% for dep, i in deps %}
            {% if dep.is_a?(TupleLiteral) %}
              {{ block.args[i] }} : {{ dep[0] }},
            {% else %}
              {{ block.args[i] }} : {{ dep }},
            {% end %}
          {% end %}
        ) { {{ block.body }} }
        %factory = -> {
          %injector.call(
            {% for dep in deps %}
              {% if dep.is_a?(TupleLiteral) %}
                Di.get_provider(Di::Registry.key({{ dep[0] }}.name, {{ dep[1].id.stringify }})).as(Di::Provider::Instance({{ dep[0] }})).resolve_typed,
              {% else %}
                Di.get_provider({{ dep }}.name).as(Di::Provider::Instance({{ dep }})).resolve_typed,
              {% end %}
            {% end %}
          )
        }
        {% if _name %}
          {% unless _name.is_a?(SymbolLiteral) %}
            {% raise "Di.provide 'as:' requires a Symbol literal, got #{_name} (use :name not a variable)" %}
          {% end %}
          %key = Di::Registry.key(typeof(%factory.call).name, {{ _name.id.stringify }})
        {% else %}
          %key = typeof(%factory.call).name
        {% end %}
        Di.register_provider(%key, Di::Provider::Instance(typeof(%factory.call)).new(%factory, transient: {{ _transient }}))
      {% end %}
    {% end %}
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
    child = Scope.new(name, parent: parent, fallback_registry: parent ? nil : registry)
    map = scope_map
    previous_scope = map[name]?
    map[name] = child
    scope_stack.push(child)
    # Increment under control mutex so shutdown!/reset! guards are atomic.
    @@control_mutex.synchronize do
      @@fiber_state_mutex.synchronize { @@global_scope_count += 1 }
    end
    body_raised = false
    begin
      yield
    rescue ex
      body_raised = true
      raise ex
    ensure
      errors = shutdown_scope(child)
      scope_stack.pop
      @@control_mutex.synchronize do
        @@fiber_state_mutex.synchronize { @@global_scope_count -= 1 }
      end
      if previous_scope
        map[name] = previous_scope
      else
        map.delete(name)
      end
      cleanup_fiber if scope_stack.empty?
      # Only raise shutdown errors when the scope body succeeded.
      # If both body and shutdown fail, the body exception takes priority.
      raise ShutdownError.new(errors) if !errors.empty? && !body_raised
    end
  end

  # Shut down all singleton providers in reverse registration order.
  #
  # Calls `.shutdown` on services that respond to it. Transient services
  # and services without `.shutdown` are skipped.
  # Raises `Di::ScopeError` if any scope is active in any fiber.
  def self.shutdown! : Nil
    providers_snapshot = @@control_mutex.synchronize do
      if @@fiber_state_mutex.synchronize { @@global_scope_count > 0 }
        raise ScopeError.new("Cannot call Di.shutdown! while scopes are active")
      end
      # Capture order and clear registry atomically under control lock.
      order = registry.reverse_order
      snapshot = order.map { |key| {key, registry.get?(key)} }
      registry.clear
      snapshot
    end

    errors = [] of Exception
    providers_snapshot.each do |key, provider|
      next unless provider
      begin
        provider.shutdown_instance
      rescue ex
        errors << ex
      end
    end
    raise ShutdownError.new(errors) unless errors.empty?
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
  # Raises `Di::ScopeNotFound` if the scope is not active in the current fiber.
  def self.healthy?(scope_name : Symbol) : Hash(String, Bool)
    map = @@fiber_state_mutex.synchronize { @@fiber_scope_maps[Fiber.current]? }
    scope = map.try(&.[scope_name]?) || raise ScopeNotFound.new(scope_name.to_s)
    collect_scope_health(scope)
  end

  # Clear all providers and scopes (test helper).
  #
  # Resets the container to a clean state. Primarily for use in specs.
  # Raises `Di::ScopeError` if any scope is active in any fiber.
  def self.reset! : Nil
    @@control_mutex.synchronize do
      if @@fiber_state_mutex.synchronize { @@global_scope_count > 0 }
        raise ScopeError.new("Cannot call Di.reset! while scopes are active")
      end
      @@registry.clear
      @@fiber_state_mutex.synchronize do
        @@fiber_scope_stacks.clear
        @@fiber_scope_maps.clear
        @@fiber_resolution_chains.clear
        @@global_scope_count = 0
      end
    end
  end

  # Remove fiber-local state for the current fiber.
  private def self.cleanup_fiber : Nil
    fiber = Fiber.current
    @@fiber_state_mutex.synchronize do
      @@fiber_scope_stacks.delete(fiber)
      @@fiber_scope_maps.delete(fiber)
      @@fiber_resolution_chains.delete(fiber)
    end
  end

  # Shutdown providers in a scope, collecting errors without aborting.
  private def self.shutdown_scope(scope : Scope) : Array(Exception)
    errors = [] of Exception
    scope.reverse_order.each do |key|
      provider = scope.get?(key)
      next unless provider
      begin
        provider.shutdown_instance
      rescue ex
        errors << ex
      end
    end
    errors
  end

  # Collect health from registry providers.
  private def self.collect_health(reg : Registry) : Hash(String, Bool)
    result = {} of String => Bool
    reg.snapshot.each do |key, provider|
      status = provider.check_health
      result[key] = status unless status.nil?
    end
    result
  end

  # Collect health from a scope, walking the parent chain and fallback registry.
  private def self.collect_scope_health(scope : Scope) : Hash(String, Bool)
    result = {} of String => Bool
    # Collect from fallback registry first (lowest priority).
    if fallback = scope.fallback_registry
      result.merge!(collect_health(fallback))
    end
    # Walk parents so child overrides take precedence.
    if parent = scope.parent
      result.merge!(collect_scope_health(parent))
    end
    scope.snapshot.each do |key, provider|
      status = provider.check_health
      result[key] = status unless status.nil?
    end
    result
  end
end

require "./di/*"
