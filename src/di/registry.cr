module Di
  # Internal registry for storing providers and tracking shutdown order.
  #
  # Key format:
  # - "Type" → default concrete registration
  # - "Type:name" → named concrete registration
  # - "~Type:Impl" → interface binding (unnamed)
  # - "~Type:Impl:name" → interface binding (named)
  #
  # Thread-safe for multi-threaded Crystal (-Dpreview_mt).
  class Registry
    extend KeyParser
    include KeyParser

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

    # Find a named interface provider by scanning for ~Type:Impl:name pattern.
    # Raises AmbiguousServiceError if multiple matches, ServiceNotFound if none.
    def find_by_name(interface_type : String, name : String) : Provider::Base
      resolve_ambiguous(find_all_by_name(interface_type, name), interface_type, name)
    end

    # Find all named interface providers matching ~Type:Impl:name pattern.
    def find_all_by_name(interface_type : String, name : String) : Array(Provider::Base)
      match_by_name_keyed(interface_type, name).values
    end

    # Find all named interface providers keyed by full key.
    def find_all_by_name_keyed(interface_type : String, name : String) : Hash(String, Provider::Base)
      match_by_name_keyed(interface_type, name)
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

    # Get all providers for an interface type (keys starting with "~Type:").
    def get_all(interface_type : String) : Array(Provider::Base)
      match_by_prefix(interface_type).values
    end

    # Get all providers keyed by full key for deduplication in child scopes.
    def get_all_keyed(interface_type : String) : Hash(String, Provider::Base)
      match_by_prefix(interface_type)
    end

    # Count implementations for an interface type.
    def count_implementations(interface_type : String) : Int32
      prefix = interface_prefix(interface_type)
      @mutex.synchronize { @providers.count { |k, _| k.starts_with?(prefix) } }
    end

    # Get implementation names for an interface type.
    def implementation_names(interface_type : String) : Array(String)
      prefix = interface_prefix(interface_type)
      match_by_prefix(interface_type).keys.map { |k| k[prefix.size..] }
    end

    # Remove a provider by key (used for rollback on partial registration failure).
    def delete(key : String) : Nil
      @mutex.synchronize do
        @providers.delete(key)
        @order.delete(key)
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
    def each(& : String, Provider::Base ->)
      @mutex.synchronize { @providers.each { |k, v| yield k, v } }
    end

    # Return a snapshot of all providers for iteration without holding mutex.
    def snapshot : Hash(String, Provider::Base)
      @mutex.synchronize { @providers.dup }
    end

    # Number of registered providers.
    def size : Int32
      @mutex.synchronize { @providers.size }
    end

    # Select providers matching interface prefix "~Type:".
    private def match_by_prefix(interface_type : String) : Hash(String, Provider::Base)
      prefix = interface_prefix(interface_type)
      @mutex.synchronize { @providers.select { |k, _| k.starts_with?(prefix) } }
    end

    # Select providers matching named interface pattern ~Type:Impl:name.
    private def match_by_name_keyed(interface_type : String, name : String) : Hash(String, Provider::Base)
      prefix = interface_prefix(interface_type)
      suffix = ":#{name}"
      min_len = prefix.size + suffix.size + 1
      @mutex.synchronize do
        @providers.select { |k, _| k.size >= min_len && k.starts_with?(prefix) && k.ends_with?(suffix) }
      end
    end
  end
end
