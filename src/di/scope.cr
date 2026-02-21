module Di
  # A scope provides isolated provider registration with parent inheritance.
  # Child scopes shadow parent providers without modifying them.
  # Thread-safe for multi-threaded Crystal (-Dpreview_mt).
  class Scope
    include KeyParser

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

    # Find a named interface provider, raising on ambiguity or not found.
    def find_by_name(interface_type : String, name : String) : Provider::Base
      resolve_ambiguous(find_all_by_name(interface_type, name), interface_type, name)
    end

    # Find all named interface providers matching ~Type:Impl:name across scope chain.
    # Child shadows parent by ALIAS NAME, not by full key.
    def find_all_by_name(interface_type : String, name : String) : Array(Provider::Base)
      local_matches = match_by_name_keyed(interface_type, name)
      return local_matches.values unless local_matches.empty?
      ancestor_matches = @parent.try(&.find_all_by_name(interface_type, name)) ||
                         @fallback_registry.try(&.find_all_by_name(interface_type, name)) ||
                         [] of Provider::Base
      ancestor_matches
    end

    # Find all named interface providers keyed for deduplication in child scopes.
    def find_all_by_name_keyed(interface_type : String, name : String) : Hash(String, Provider::Base)
      local_matches = match_by_name_keyed(interface_type, name)
      return local_matches unless local_matches.empty?

      merge_with_ancestors(&.find_all_by_name_keyed(interface_type, name))
    end

    # Get all providers for an interface type across scope chain.
    # Child shadows parent by IMPL KEY (Type:Impl segment).
    def get_all(interface_type : String) : Array(Provider::Base)
      merge_with_ancestors(&.get_all_keyed(interface_type))
        .merge(match_by_prefix(interface_type))
        .values
    end

    # Get all providers keyed by full key for deduplication in child scopes.
    def get_all_keyed(interface_type : String) : Hash(String, Provider::Base)
      merge_with_ancestors(&.get_all_keyed(interface_type))
        .merge(match_by_prefix(interface_type))
    end

    # Count implementations for an interface type across scope chain.
    def count_implementations(interface_type : String) : Int32
      get_all(interface_type).size
    end

    # Get implementation names for an interface type across scope chain.
    def implementation_names(interface_type : String) : Array(String)
      prefix = interface_prefix(interface_type)
      get_all_keyed(interface_type).keys.map { |k| k[prefix.size..] }
    end

    # Get a provider by key, checking parent scope then fallback registry.
    def get?(key : String) : Provider::Base?
      @mutex.synchronize { @providers[key]? } ||
        @parent.try(&.get?(key)) ||
        @fallback_registry.try(&.get?(key))
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
      @mutex.synchronize { @providers.has_key?(key) } ||
        @parent.try(&.registered?(key)) ||
        @fallback_registry.try(&.registered?(key)) ||
        false
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
    def each(& : String, Provider::Base ->)
      @mutex.synchronize { @providers.each { |k, v| yield k, v } }
    end

    # Return a snapshot of local providers for iteration without holding mutex.
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

    # Walk parent chain or fallback registry for inherited providers.
    private def merge_with_ancestors(& : Scope | Registry -> Hash(String, Provider::Base)) : Hash(String, Provider::Base)
      @parent.try { |parent| yield parent } ||
        @fallback_registry.try { |fallback| yield fallback } ||
        {} of String => Provider::Base
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
