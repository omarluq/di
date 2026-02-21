module Di
  # Internal registry for storing providers and tracking shutdown order.
  # Uses a string key format: "TypeName" for default, "TypeName/name" for named providers.
  # Thread-safe for multi-threaded Crystal (-Dpreview_mt).
  class Registry
    @providers = {} of String => Provider::Base
    @order = [] of String
    @mutex = Mutex.new

    # Register a provider with the given key.
    # Raises AlreadyRegistered if the key already exists.
    def register(key : String, provider : Provider::Base) : Nil
      @mutex.synchronize do
        raise AlreadyRegistered.new(*parse_key(key)) if @providers.has_key?(key)
        @providers[key] = provider
        @order << key
      end
    end

    # Get a provider by key, or nil if not registered.
    def get?(key : String) : Provider::Base?
      @mutex.synchronize { @providers[key]? }
    end

    # Get a provider by key, raising ServiceNotFound if not registered.
    def get(key : String) : Provider::Base
      @mutex.synchronize do
        @providers[key]? || raise ServiceNotFound.new(*parse_key(key))
      end
    end

    # Check if a provider is registered for the given key.
    def registered?(key : String) : Bool
      @mutex.synchronize { @providers.has_key?(key) }
    end

    # Return all registered keys in registration order.
    def order : Array(String)
      @mutex.synchronize { @order.dup }
    end

    # Return all registered keys in reverse order (for shutdown).
    def reverse_order : Array(String)
      @mutex.synchronize { @order.reverse }
    end

    # Clear all providers and reset order.
    def clear : Nil
      @mutex.synchronize do
        @providers.clear
        @order.clear
      end
    end

    # Iterate over all providers with their keys.
    # Note: Holds mutex for the duration of iteration.
    def each(& : String, Provider::Base ->)
      @mutex.synchronize { @providers.each { |k, v| yield k, v } }
    end

    # Return a snapshot of all providers for iteration without holding mutex.
    # Use this when callbacks may call back into Di (e.g., health checks).
    def snapshot : Hash(String, Provider::Base)
      @mutex.synchronize { @providers.dup }
    end

    # Number of registered providers.
    def size : Int32
      @mutex.synchronize { @providers.size }
    end

    # Build a registry key from type name and optional service name.
    def self.key(type_name : String, service_name : String? = nil) : String
      service_name ? "#{type_name}/#{service_name}" : type_name
    end

    # Parse a registry key into (type_name, service_name) tuple.
    private def parse_key(key : String) : {String, String?}
      return {key, nil} unless key.includes?('/')
      parts = key.split('/', 2)
      {parts[0], parts[1]}
    end
  end
end
