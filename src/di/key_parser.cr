module Di
  # Shared key parsing utilities for Registry and Scope.
  # Handles Crystal namespaced types (e.g. "NS::C:name") correctly.
  #
  # Key format:
  # - "Type" → default concrete registration
  # - "Type:name" → named concrete registration
  # - "~Type:Impl" → interface binding (unnamed)
  # - "~Type:Impl:name" → interface binding (named)
  #
  # The "~" prefix ensures interface bindings don't leak into concrete resolution.
  module KeyParser
    # Marker prefix for interface binding keys.
    INTERFACE_PREFIX = "~"

    # Parse a registry key into (type_name, service_name) tuple.
    # Finds the first single ':' that isn't part of '::' namespace separator.
    # Strips interface marker from type_name if present.
    def parse_key(key : String) : {String, String?}
      # Strip interface marker for error messages
      key = key[1..] if key.starts_with?(INTERFACE_PREFIX)
      idx = 0
      while idx < key.size
        if key[idx] == ':'
          if idx + 1 < key.size && key[idx + 1] == ':'
            idx += 2 # skip '::' namespace separator
          else
            return {key[0...idx], key[idx + 1..]}
          end
        else
          idx += 1
        end
      end
      {key, nil}
    end

    # Build a registry key from segments joined by ':'.
    # key(type: "Type") → "Type"
    # key(type: "Type", name: "primary") → "Type:primary"
    # key(type: "Type", impl: "Impl") → "~Type:Impl"
    # key(type: "Type", impl: "Impl", name: "primary") → "~Type:Impl:primary"
    def key(type : String, impl : String? = nil, name : String? = nil) : String
      result = type
      result = "#{result}:#{impl}" if impl
      result = "#{result}:#{name}" if name
      result = INTERFACE_PREFIX + result if impl
      result
    end

    # Build interface lookup prefix for scanning.
    def interface_prefix(interface_type : String) : String
      "#{INTERFACE_PREFIX}#{interface_type}:"
    end

    # Strip interface marker and extract display-friendly implementation name.
    # "~Type:Impl:name" → "Impl:name", "~NS::Type:NS::Impl" → "NS::Impl"
    private def display_impl_name(key : String) : String
      key = key[1..] if key.starts_with?(INTERFACE_PREFIX)
      _, rest = parse_key(key)
      rest || key
    end

    # Check for ambiguous named matches and return single provider or raise.
    def resolve_ambiguous(matches : Array(Provider::Base), interface_type : String, name : String) : Provider::Base
      return matches.first if matches.size == 1
      impl_names = matches.map { |provider| provider.key ? display_impl_name(provider.key.as(String)) : "unknown" }
      raise AmbiguousServiceError.new(interface_type, impl_names) if matches.size > 1
      raise ServiceNotFound.new(interface_type, name)
    end

    # Like resolve_ambiguous, but returns nil instead of raising ServiceNotFound.
    def resolve_ambiguous?(matches : Array(Provider::Base), interface_type : String) : Provider::Base?
      return matches.first if matches.size == 1
      return nil if matches.empty?
      impl_names = matches.map { |provider| provider.key ? display_impl_name(provider.key.as(String)) : "unknown" }
      raise AmbiguousServiceError.new(interface_type, impl_names)
    end
  end
end
