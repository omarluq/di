require "mutex"
require "./di/errors"
require "./di/provider"
require "./di/key_parser"

module Di
  extend KeyParser

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
    raise CircularDependency.new(chain + [type_name]) if chain.includes?(type_name)
    chain << type_name
    begin
      yield
    ensure
      chain.pop
      @@fiber_state_mutex.synchronize { @@fiber_resolution_chains.delete(Fiber.current) } if chain.empty?
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
    resolve_target.register(key, provider)
  end

  # Returns the active scope or falls back to the root registry.
  # Both Scope and Registry share the same provider lookup interface.
  private def self.resolve_target
    current_scope || registry
  end

  # Get a provider from the current scope chain (or root registry).
  # Tries exact key first, then interface prefix scan.
  def self.get_provider(key : String) : Provider::Base
    target = resolve_target
    provider = target.get?(key)
    return provider if provider
    count = target.count_implementations(key)
    raise AmbiguousServiceError.new(key, target.implementation_names(key)) if count > 1
    return target.get_all(key).first if count == 1
    raise ServiceNotFound.new(key)
  end

  # Get a provider from the current scope chain, returning nil if not found.
  def self.get_provider?(key : String) : Provider::Base?
    target = resolve_target
    provider = target.get?(key)
    return provider if provider
    count = target.count_implementations(key)
    raise AmbiguousServiceError.new(key, target.implementation_names(key)) if count > 1
    return target.get_all(key).first if count == 1
    nil
  end

  # Get a named provider by trying exact key (Type:name) then interface scan (Type:Impl:name).
  # Raises AmbiguousServiceError if multiple interface impls share the same name.
  def self.get_named_provider(type_name : String, name : String) : Provider::Base
    target = resolve_target
    target.get?(key(type_name, name: name)) ||
      target.find_by_name(type_name, name)
  end

  # Get a named provider, returning nil if not found.
  # Raises AmbiguousServiceError if multiple interface impls share the same name.
  def self.get_named_provider?(type_name : String, name : String) : Provider::Base?
    target = resolve_target
    target.get?(key(type_name, name: name)) ||
      resolve_ambiguous?(target.find_all_by_name(type_name, name), type_name)
  end

  # Get all providers for an interface type from the current scope chain.
  def self.get_all_providers(interface_type : String) : Array(Provider::Base)
    resolve_target.get_all(interface_type)
  end

  # :nodoc: Internal API. Use inside factory blocks at top-level where macro
  # ordering prevents `Di[Type]`. Returns exactly `T`, no casting.
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
  # db = Di[Database]
  # primary = Di[Database, :primary]
  # ```
  #
  # Raises `Di::ServiceNotFound` if the type is not registered.
  macro [](type, name = nil)
    {% raise "Di[] name requires a Symbol literal, got #{name} (use :name not a variable)" if name && !name.is_a?(SymbolLiteral) %}
    {% if type.is_a?(Generic) && type.name.resolve == Array %}
      {% raise "Di[Array(T)] does not support named resolution" if name %}
      {% inner = type.type_vars[0] %}
      Di.get_all_providers({{ inner }}.name).map { |provider| provider.as(Di::Provider::Instance({{ inner }})).resolve_typed }
    {% elsif name %}
      Di.get_named_provider({{ type }}.name, {{ name.id.stringify }}).as(Di::Provider::Instance({{ type }})).resolve_typed
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
  # db = Di[Database]?
  # replica = Di[Database, :replica]?
  # ```
  macro []?(type, name = nil)
    {% raise "Di[]? name requires a Symbol literal, got #{name} (use :name not a variable)" if name && !name.is_a?(SymbolLiteral) %}
    {% if type.is_a?(Generic) && type.name.resolve == Array %}
      {% raise "Di[Array(T)]? does not support named resolution" if name %}
      {% inner = type.type_vars[0] %}
      %all = Di.get_all_providers({{ inner }}.name)
      %all.map { |provider| provider.as(Di::Provider::Instance({{ inner }})).resolve_typed } unless %all.empty?
    {% elsif name %}
      %provider = Di.get_named_provider?({{ type }}.name, {{ name.id.stringify }})
      %provider.as(Di::Provider::Instance({{ type }})).resolve_typed if %provider
    {% else %}
      %provider = Di.get_provider?({{ type }}.name)
      %provider.as(Di::Provider::Instance({{ type }})).resolve_typed if %provider
    {% end %}
  end

  # Resolve a service by type.
  #
  # **Deprecated**: Use `Di[Type]` instead. This alias exists for backward
  # compatibility but the bracket syntax is preferred for idiomatic Crystal.
  #
  # Example:
  # ```
  # db = Di.invoke(Database)                # deprecated
  # db = Di[Database]                       # preferred
  # primary = Di.invoke(Database, :primary) # deprecated
  # primary = Di[Database, :primary]        # preferred
  # ```
  #
  # Raises `Di::ServiceNotFound` if the type is not registered.
  macro invoke(type, name = nil)
    Di[{{ type }}, {{ name }}]
  end

  # Resolve a service by type, returning nil if not registered.
  #
  # **Deprecated**: Use `Di[Type]?` instead. This alias exists for backward
  # compatibility but the bracket syntax is preferred for idiomatic Crystal.
  #
  # Example:
  # ```
  # db = Di.invoke?(Database) # deprecated
  # db = Di[Database]?        # preferred
  # ```
  macro invoke?(type, name = nil)
    Di[{{ type }}, {{ name }}]?
  end

  # Register a service provider.
  #
  # No block (auto-wire):
  # - `Di.provide UserService`
  # - `Di.provide UserService, as: :primary`
  #
  # Interface binding (2 types, no block):
  # - `Di.provide Printable, Square`  # register Square under Printable key
  # - `Di.provide Printable, Square, as: :primary`
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
    # Guard: validate _name is a Symbol literal once (applies to all paths).
    {% raise "Di.provide 'as:' requires a Symbol literal, got #{_name} (use :name not a variable)" if _name && !_name.is_a?(SymbolLiteral) %}

    {% if block.is_a?(Nop) %}
      # No-block path: auto-wire or interface binding
      {% raise "Di.provide requires at least one type argument" if deps.size == 0 %}
      {% raise "Di.provide auto-wire requires 1 or 2 types, got #{deps.size}" if deps.size > 2 %}

      # Normalize: provider_type is the registry key type, construct_type builds the instance.
      # Di.provide Service        → both are Service
      # Di.provide Printable, Sq  → provider=Printable, construct=Square
      {% provider_type = deps[0] %}
      {% construct_type = deps.size == 2 ? deps[1] : deps[0] %}

      {% raise "Di.provide interface binding: #{construct_type} must include or inherit from #{provider_type}" if deps.size == 2 && !construct_type.resolve.ancestors.any? { |ancestor| ancestor == provider_type.resolve } %}

      {% init_method = construct_type.resolve.methods.find { |method| method.name == "initialize" } %}
      {% if init_method %}
        {% for arg in init_method.args %}
          {% raise "Di.provide auto-wire requires type restriction on argument '#{arg.name}' in #{construct_type}#initialize" if arg.restriction.nil? %}
        {% end %}
        %factory = -> : {{ provider_type }} {
          {{ construct_type }}.new(
            {% for arg in init_method.args %}
              {{ arg.name }}: Di[{{ arg.restriction }}],
            {% end %}
          )
        }
      {% else %}
        %factory = -> : {{ provider_type }} { {{ construct_type }}.new }
      {% end %}

      {% if deps.size == 2 %}
        # Interface binding: key is Type:Impl or Type:Impl:name.
        {% key_name = _name ? _name.id.stringify : nil %}
        %key = Di::Registry.key({{ provider_type }}.name, impl: {{ construct_type }}.name, name: {{ key_name }})
      {% else %}
        # Single type: key is Type or Type:name.
        {% key_name = _name ? _name.id.stringify : nil %}
        %key = Di::Registry.key({{ provider_type }}.name, name: {{ key_name }})
      {% end %}
      Di.register_provider(%key, Di::Provider::Instance({{ provider_type }}).new(%factory, transient: {{ _transient }}))

    {% else %}
      # Block path: explicit factory
      {% raise "Di.provide block arguments require dependency types: Di.provide(Type1, ...) { |...| ... }" if deps.empty? && block.args.size > 0 %}
      {% raise "Di.provide block expects #{deps.size} argument(s) for #{deps.size} dependency type(s), got #{block.args.size}" if !deps.empty? && block.args.size != deps.size %}

      # Validate named dependency tuples before building factory
      {% for dep in deps %}
          {% raise "Di.provide named dependency must use {Type, :name}, got #{dep}" if dep.is_a?(TupleLiteral) && dep.size != 2 %}
          {% raise "Di.provide dependency name requires a Symbol literal in {Type, :name}, got #{dep[1]}" if dep.is_a?(TupleLiteral) && !dep[1].is_a?(SymbolLiteral) %}
      {% end %}

      {% if deps.empty? %}
        # Simple block: Di.provide { Service.new }
        %factory = -> { {{ block.body }} }
        {% key_name = _name ? _name.id.stringify : nil %}
        %key = {{ _name }} ? Di::Registry.key(typeof({{ block.body }}).name, name: {{ key_name }}) : typeof({{ block.body }}).name
        Di.register_provider(%key, Di::Provider::Instance(typeof({{ block.body }})).new(%factory, transient: {{ _transient }}))

      {% else %}
        # Block with deps: Di.provide(A, B) { |a, b| C.new(a, b) }
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
                Di.get_named_provider({{ dep[0] }}.name, {{ dep[1].id.stringify }}).as(Di::Provider::Instance({{ dep[0] }})).resolve_typed,
              {% else %}
                Di.get_provider({{ dep }}.name).as(Di::Provider::Instance({{ dep }})).resolve_typed,
              {% end %}
            {% end %}
          )
        }
        {% key_name = _name ? _name.id.stringify : nil %}
        %key = {{ _name }} ? Di::Registry.key(typeof(%factory.call).name, name: {{ key_name }}) : typeof(%factory.call).name
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
  #   user = Di[CurrentUser]
  # end
  # ```
  def self.scope(name : Symbol, &)
    parent = current_scope
    fallback = parent ? nil : registry
    child = Scope.new(name, parent: parent, fallback_registry: fallback)
    # Increment scope count BEFORE publishing fiber-local state so
    # shutdown!/reset! guards see the count before any state is visible.
    @@control_mutex.synchronize do
      @@fiber_state_mutex.synchronize { @@global_scope_count += 1 }
    end
    map = scope_map
    previous_scope = map[name]?
    map[name] = child
    scope_stack.push(child)
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
      previous_scope.try { |prev| map[name] = prev } || map.delete(name)
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
      raise ScopeError.new("Cannot call Di.shutdown! while scopes are active") if global_scope_active?
      # Capture order and clear registry atomically under control lock.
      order = registry.reverse_order
      snapshot = order.map { |key| {key, registry.get?(key)} }
      registry.clear
      snapshot
    end

    errors = [] of Exception
    # Deduplicate by object_id to avoid double-shutdown for aliased providers.
    seen = Set(UInt64).new
    providers_snapshot.each do |_key, provider|
      next unless provider
      next unless seen.add?(provider.object_id)
      provider.shutdown_instance
    rescue ex
      errors << ex
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
      raise ScopeError.new("Cannot call Di.reset! while scopes are active") if global_scope_active?
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
  # Deduplicates by object_id to avoid double-shutdown for aliased providers.
  private def self.shutdown_scope(scope : Scope) : Array(Exception)
    errors = [] of Exception
    seen = Set(UInt64).new
    scope.reverse_order.each do |key|
      provider = scope.get?(key) || next
      next unless seen.add?(provider.object_id)
      provider.shutdown_instance
    rescue ex
      errors << ex
    end
    errors
  end

  # Collect health from registry providers.
  private def self.collect_health(reg : Registry) : Hash(String, Bool)
    result = {} of String => Bool
    reg.snapshot.each do |key, provider|
      provider.check_health.try { |status| result[key] = status }
    end
    result
  end

  # Collect health from a scope, walking the parent chain and fallback registry.
  private def self.collect_scope_health(scope : Scope) : Hash(String, Bool)
    result = {} of String => Bool
    # Collect from fallback registry first (lowest priority).
    scope.fallback_registry.try { |fallback| result.merge!(collect_health(fallback)) }
    # Walk parents so child overrides take precedence.
    scope.parent.try { |parent| result.merge!(collect_scope_health(parent)) }
    scope.snapshot.each do |key, provider|
      provider.check_health.try { |status| result[key] = status }
    end
    result
  end
end

require "./di/*"
