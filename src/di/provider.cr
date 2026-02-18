module Di
  # Namespace for provider types.
  module Provider
    # Abstract base for type-erased provider storage in the registry.
    # Only includes methods that don't need type info.
    abstract class Base
      abstract def transient? : Bool
      abstract def reset! : Nil

      # Attempt to call .shutdown on the cached instance (if any).
      # No-op for transient providers or unresolved singletons.
      def shutdown_instance : Nil
      end

      # Attempt to call .healthy? on the cached instance.
      # Returns nil if not resolved, transient, or service doesn't respond.
      def check_health : Bool?
        nil
      end
    end

    # Generic provider that stores a typed factory and optional singleton cache.
    #
    # Singleton (default): the factory runs once on first resolve, result is cached.
    # Transient: the factory runs on every resolve, nothing is cached.
    class Instance(T) < Base
      @instance : T? = nil

      def initialize(@factory : -> T, @transient : Bool = false)
      end

      # Type-safe resolve — returns exactly T.
      def resolve_typed : T
        return @factory.call if @transient
        @instance ||= @factory.call
      end

      def transient? : Bool
        @transient
      end

      # Returns the cached singleton instance, or nil if not yet resolved or transient.
      def instance : T?
        @instance
      end

      def reset! : Nil
        @instance = nil
      end

      # Call .shutdown on the cached instance if it responds to it.
      def shutdown_instance : Nil
        return if @transient
        if inst = @instance
          inst.shutdown if inst.responds_to?(:shutdown)
        end
      end

      # Call .healthy? on the cached instance if it responds to it.
      def check_health : Bool?
        if inst = @instance
          if inst.responds_to?(:healthy?)
            inst.healthy?
          end
        end
      end
    end
  end
end
