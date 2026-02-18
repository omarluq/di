# Test helper classes for spec files.
#
# Contains utility classes that aid in testing but aren't
# mock implementations of production code.
module TestHelpers
  # Returns the number of fibers currently tracked with scope state.
  # Only available in test builds for memory leak assertions.
  def self.fiber_state_count : Int32
    # Access internal tracking via Di's private state.
    # This uses Crystal's ability to call private methods from same namespace.
    Di.fiber_state_count_internal
  end
end

# Internal helper exposed only for test assertions.
module Di
  def self.fiber_state_count_internal : Int32
    @@fiber_state_mutex.synchronize { @@fiber_scope_stacks.size }
  end
end
