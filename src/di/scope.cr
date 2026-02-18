module Di
  # A scope provides isolated provider registration with parent inheritance.
  # Child scopes shadow parent providers without modifying them.
  class Scope
    getter name : Symbol
    getter parent : Scope?

    @providers = {} of String => Provider::Base
    @order = [] of String

    def initialize(@name : Symbol, @parent : Scope? = nil)
    end

    # Register a provider with the given key.
    # Raises AlreadyRegistered if the key already exists in this scope.
    def register(key : String, provider : Provider::Base) : Nil
      raise AlreadyRegistered.new(*parse_key(key)) if @providers.has_key?(key)
      @providers[key] = provider
      @order << key
    end

    # Get a provider by key, checking parent scope if not found locally.
    def get?(key : String) : Provider::Base?
      @providers[key]? || @parent.try(&.get?(key))
    end

    # Get a provider by key, raising ServiceNotFound if not in scope chain.
    def get(key : String) : Provider::Base
      get?(key) || raise ServiceNotFound.new(*parse_key(key))
    end

    # Check if a provider is registered in this scope or any parent.
    def registered?(key : String) : Bool
      @providers.has_key?(key) || @parent.try(&.registered?(key)) || false
    end

    # Check if a provider is registered locally in this scope only.
    def local?(key : String) : Bool
      @providers.has_key?(key)
    end

    # Return keys in registration order for this scope only.
    def order : Array(String)
      @order.dup
    end

    # Return keys in reverse order for shutdown (this scope only).
    def reverse_order : Array(String)
      @order.reverse
    end

    # Iterate over local providers only.
    def each(& : String, Provider::Base ->)
      @providers.each { |k, v| yield k, v }
    end

    # Number of local providers.
    def size : Int32
      @providers.size
    end

    # Clear local providers only (does not affect parent).
    def clear : Nil
      @providers.clear
      @order.clear
    end

    private def parse_key(key : String) : {String, String?}
      if key.includes?('/')
        parts = key.split('/', 2)
        {parts[0], parts[1]}
      else
        {key, nil}
      end
    end
  end
end
