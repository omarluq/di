module Di
  # A scope provides isolated provider registration with parent inheritance.
  # Child scopes shadow parent providers without modifying them.
  # Thread-safe for multi-threaded Crystal (-Dpreview_mt).
  class Scope
    getter name : Symbol
    getter parent : Scope?
    getter fallback_registry : Registry?

    @providers = {} of String => Provider::Base
    @order = [] of String
    @mutex = Mutex.new

    def initialize(@name : Symbol, @parent : Scope? = nil, @fallback_registry : Registry? = nil)
    end

    # Register a provider with the given key.
    # Raises AlreadyRegistered if the key already exists in this scope.
    def register(key : String, provider : Provider::Base) : Nil
      @mutex.synchronize do
        raise AlreadyRegistered.new(*parse_key(key)) if @providers.has_key?(key)
        @providers[key] = provider
        @order << key
      end
    end

    # Register an interface binding with implementation tracking.
    def register_interface(interface_type : String, impl_type : String, provider : Provider::Base) : Nil
      key = "#{interface_type}:#{impl_type}"
      @mutex.synchronize do
        raise AlreadyRegistered.new(interface_type, impl_type) if @providers.has_key?(key)
        @providers[key] = provider
        @order << key
      end
    end

    # Get all providers for an interface type across scope chain.
    # Local providers shadow parent/fallback providers with the same impl key.
    def get_all(interface_type : String) : Array(Provider::Base)
      prefix = "#{interface_type}:"
      local_map = @mutex.synchronize { @providers.select { |k, _| k.starts_with?(prefix) } }
      parent_map = @parent.try(&.get_all_keyed(interface_type)) || @fallback_registry.try(&.get_all_keyed(interface_type)) || {} of String => Provider::Base
      parent_map.merge(local_map).values
    end

    # Get all providers keyed by full key for deduplication in child scopes.
    def get_all_keyed(interface_type : String) : Hash(String, Provider::Base)
      prefix = "#{interface_type}:"
      local_map = @mutex.synchronize { @providers.select { |k, _| k.starts_with?(prefix) } }
      parent_map = @parent.try(&.get_all_keyed(interface_type)) || @fallback_registry.try(&.get_all_keyed(interface_type)) || {} of String => Provider::Base
      parent_map.merge(local_map)
    end

    # Count implementations for an interface type across scope chain.
    def count_implementations(interface_type : String) : Int32
      get_all(interface_type).size
    end

    # Get implementation names for an interface type across scope chain.
    def implementation_names(interface_type : String) : Array(String)
      prefix = "#{interface_type}:"
      local_map = @mutex.synchronize { @providers.select { |k, _| k.starts_with?(prefix) } }
      parent_map = @parent.try(&.get_all_keyed(interface_type)) || @fallback_registry.try(&.get_all_keyed(interface_type)) || {} of String => Provider::Base
      parent_map.merge(local_map).keys.map { |k| k[prefix.size..] }
    end

    # Get a provider by key, checking parent scope then fallback registry.
    def get?(key : String) : Provider::Base?
      @mutex.synchronize { @providers[key]? } || @parent.try(&.get?(key)) || @fallback_registry.try(&.get?(key))
    end

    # Get a provider by key, raising ServiceNotFound if not in scope chain.
    def get(key : String) : Provider::Base
      get?(key) || raise ServiceNotFound.new(*parse_key(key))
    end

    # Remove a provider by key (used for rollback on partial registration failure).
    def delete(key : String) : Nil
      @mutex.synchronize do
        @providers.delete(key)
        @order.delete(key)
      end
    end

    # Check if a provider is registered in this scope, parent, or fallback registry.
    def registered?(key : String) : Bool
      @mutex.synchronize { @providers.has_key?(key) } || @parent.try(&.registered?(key)) || @fallback_registry.try(&.registered?(key)) || false
    end

    # Check if a provider is registered locally in this scope only.
    def local?(key : String) : Bool
      @mutex.synchronize { @providers.has_key?(key) }
    end

    # Return keys in registration order for this scope only.
    def order : Array(String)
      @mutex.synchronize { @order.dup }
    end

    # Return keys in reverse order for shutdown (this scope only).
    def reverse_order : Array(String)
      @mutex.synchronize { @order.reverse }
    end

    # Iterate over local providers only.
    # Note: Holds mutex for the duration of iteration.
    def each(& : String, Provider::Base ->)
      @mutex.synchronize { @providers.each { |k, v| yield k, v } }
    end

    # Return a snapshot of local providers for iteration without holding mutex.
    # Use this when callbacks may call back into Di (e.g., health checks).
    def snapshot : Hash(String, Provider::Base)
      @mutex.synchronize { @providers.dup }
    end

    # Number of local providers.
    def size : Int32
      @mutex.synchronize { @providers.size }
    end

    # Clear local providers only (does not affect parent).
    def clear : Nil
      @mutex.synchronize do
        @providers.clear
        @order.clear
      end
    end

    private def parse_key(key : String) : {String, String?}
      return {key, nil} unless key.includes?('/')
      parts = key.split('/', 2)
      {parts[0], parts[1]}
    end
  end
end
