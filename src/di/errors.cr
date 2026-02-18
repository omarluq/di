module Di
  # Base error for all Di exceptions.
  class Error < Exception; end

  # Raised when resolving a service that was never registered.
  class ServiceNotFound < Error
    getter type_name : String
    getter service_name : String?

    def initialize(@type_name, @service_name = nil)
      label = @service_name ? "#{@type_name}/#{@service_name}" : @type_name
      super("Service not registered: #{label}")
    end
  end

  # Raised when auto-wire detects a dependency cycle.
  class CircularDependency < Error
    getter chain : Array(String)

    def initialize(@chain)
      super("Circular dependency detected: #{@chain.join(" -> ")}")
    end
  end

  # Raised when registering a service that already exists under the same key.
  class AlreadyRegistered < Error
    getter type_name : String
    getter service_name : String?

    def initialize(@type_name, @service_name = nil)
      label = @service_name ? "#{@type_name}/#{@service_name}" : @type_name
      super("Service already registered: #{label}")
    end
  end

  # Raised at runtime when referencing an unknown scope.
  class ScopeNotFound < Error
    getter scope_name : String

    def initialize(@scope_name)
      super("Scope not found: #{@scope_name}")
    end
  end

  # Raised when an invalid scope operation is attempted.
  class ScopeError < Error
  end
end
