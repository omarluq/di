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
    Di[ShutdownTracker]
    Di[NoShutdownService]

    # Register a second tracker under a named key.
    Di.provide(as: :second) { ShutdownTracker.new(3) }
    Di[ShutdownTracker, :second]

    Di.shutdown!

    # Only ShutdownTrackers get shutdown; order is reverse registration.
    ShutdownTracker.order.should eq([3, 1])
  end

  it "skips transient providers" do
    Di.provide(transient: true) { ShutdownTracker.new(99) }
    Di[ShutdownTracker]

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
    Di[ShutdownTracker]

    Di.shutdown!

    Di.registry.registered?("ShutdownTracker").should be_false
  end

  it "raises ScopeError when called while scopes are active" do
    Di.provide { ShutdownTracker.new(1) }

    Di.scope(:inner) do
      expect_raises(Di::ScopeError, /while scopes are active/) do
        Di.shutdown!
      end
    end
  end

  it "continues shutdown and clears registry even when a service raises" do
    shutdown_svc = ShutdownTracker.new(1)
    Di.provide { shutdown_svc }
    Di.provide { FailingShutdownService.new }
    Di[ShutdownTracker]
    Di[FailingShutdownService]

    error = expect_raises(Di::ShutdownError) { Di.shutdown! }
    error.errors.size.should eq(1)
    error.errors.first.message.should eq("shutdown failed")

    # Registry is cleared even after failure
    Di.registry.registered?("ShutdownTracker").should be_false
    # First service was still shut down
    ShutdownTracker.order.should eq([1])
  end

  it "calls each singleton shutdown exactly once under concurrent calls" do
    AtomicShutdownTracker.reset
    Di.provide { AtomicShutdownTracker.new }
    Di[AtomicShutdownTracker]

    done = Channel(Nil).new(3)
    3.times do
      spawn do
        Di.shutdown! rescue nil
        done.send(nil)
      rescue
        done.send(nil)
      end
    end

    3.times { done.receive }
    AtomicShutdownTracker.count.should eq(1)
  end
end

private class FailingShutdownService
  def shutdown
    raise "shutdown failed"
  end
end

private class AtomicShutdownTracker
  @@count = Atomic(Int32).new(0)

  def self.count
    @@count.get
  end

  def self.reset
    @@count.set(0)
  end

  def shutdown
    @@count.add(1)
  end
end
