module Di
  # Namespace for provider types.
  module Provider
    # Abstract base for type-erased provider storage in the registry.
    # Only includes methods that don't need type info.
    abstract class Base
      abstract def transient? : Bool
      abstract def reset! : Nil
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
    end
  end
end
