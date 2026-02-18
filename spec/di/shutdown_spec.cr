require "../spec_helper"

private class ShutdownTracker
  class_getter order = [] of Int32

  getter id : Int32

  def initialize(@id : Int32)
  end

  def shutdown
    self.class.order << @id
  end
end

private class NoShutdownService
  getter id : Int32

  def initialize(@id = 0)
  end
end

describe "Di.shutdown!" do
  before_each { ShutdownTracker.order.clear }

  it "calls shutdown on singleton providers in reverse registration order" do
    Di.provide { ShutdownTracker.new(1) }
    Di.provide { NoShutdownService.new(2) }

    # Resolve singletons so instances are cached.
    Di.invoke(ShutdownTracker)
    Di.invoke(NoShutdownService)

    # Register a second tracker under a named key.
    Di.provide(as: :second) { ShutdownTracker.new(3) }
    Di.invoke(ShutdownTracker, :second)

    Di.shutdown!

    # Only ShutdownTrackers get shutdown; order is reverse registration.
    ShutdownTracker.order.should eq([3, 1])
  end

  it "skips transient providers" do
    Di.provide(transient: true) { ShutdownTracker.new(99) }
    Di.invoke(ShutdownTracker)

    Di.shutdown!

    ShutdownTracker.order.should be_empty
  end

  it "skips unresolved singletons" do
    Di.provide { ShutdownTracker.new(1) }
    # Never invoke — instance is nil.

    Di.shutdown!

    ShutdownTracker.order.should be_empty
  end

  it "clears the registry after shutdown" do
    Di.provide { ShutdownTracker.new(1) }
    Di.invoke(ShutdownTracker)

    Di.shutdown!

    Di.registry.registered?("ShutdownTracker").should be_false
  end
end
