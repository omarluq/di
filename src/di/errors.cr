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

  # Raised when one or more service shutdowns fail.
  class ShutdownError < Error
    getter errors : Array(Exception)

    def initialize(@errors)
      super("Shutdown failed for #{@errors.size} service(s): #{@errors.map(&.message).join(", ")}")
    end
  end

  # Raised when multiple implementations of the same interface are registered
  # and an unambiguous resolution is requested.
  class AmbiguousServiceError < Error
    getter interface_type : String
    getter implementations : Array(String)

    def initialize(@interface_type, @implementations)
      super("Ambiguous service: #{@interface_type} has #{@implementations.size} implementations (#{@implementations.join(", ")}). Use named resolution or Di.all(#{@interface_type}) for multi-resolve.")
    end
  end
end
