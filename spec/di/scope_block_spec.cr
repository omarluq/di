require "../spec_helper"

private class ScopeBlockService
  getter id : Int32

  def initialize(@id = 0)
  end
end

private class ScopeShutdownService
  getter id : Int32
  property? shutdown_called : Bool = false

  def initialize(@id = 0)
  end

  def shutdown
    @shutdown_called = true
  end
end

private class ScopeParentService
  def initialize
  end
end

private class ShadowService
  getter value : String

  def initialize(@value : String)
  end
end

describe "Di.scope" do
  describe "provider registration" do
    it "registers providers in the scope" do
      Di.provide { ScopeParentService.new }

      Di.scope(:test) do
        Di.provide { ScopeBlockService.new(42) }
        if scope = Di.current_scope
          scope.local?("ScopeBlockService").should be_true
        end
      end

      # Scope is cleaned up after block
      Di.current_scope.should be_nil
    end

    it "does not pollute parent with scope-local providers" do
      Di.provide { ScopeParentService.new }

      Di.scope(:test) do
        Di.provide { ScopeBlockService.new(42) }
      end

      Di.registry.registered?("ScopeBlockService").should be_false
    end
  end

  describe "inheritance" do
    it "inherits providers from root" do
      Di.provide { ScopeParentService.new }

      Di.scope(:test) do
        svc = Di.invoke(ScopeParentService)
        svc.should be_a(ScopeParentService)
      end
    end

    it "sees root providers registered after scope starts (live fallback)" do
      # Cross-fiber test: scope in one fiber, root registration in another.
      ready = Channel(Nil).new
      done = Channel(Nil).new
      result = Channel(ScopeParentService).new

      spawn do
        Di.scope(:cross_fiber_root) do
          ready.send(nil)
          # Wait for root registration from other fiber
          sleep 5.milliseconds
          result.send(Di.invoke(ScopeParentService))
        end
        done.send(nil)
      end

      ready.receive # Wait for scope to be active
      # Now register in ROOT (no scope active in this fiber)
      Di.provide { ScopeParentService.new }

      svc = result.receive
      svc.should be_a(ScopeParentService)

      done.receive
    end

    it "shadows parent provider with same-key override" do
      Di.provide { ShadowService.new("root") }

      Di.scope(:test) do
        Di.provide { ShadowService.new("scope") }
        Di.invoke(ShadowService).value.should eq("scope")
      end

      # Root provider unchanged after scope exits
      Di.invoke(ShadowService).value.should eq("root")
    end
  end

  describe "nested scopes" do
    it "chains through nested scopes" do
      Di.provide { ScopeParentService.new }

      Di.scope(:outer) do
        Di.provide { ScopeBlockService.new(1) }

        Di.scope(:inner) do
          # Inherits from both outer and root
          Di.invoke(ScopeParentService).should be_a(ScopeParentService)
          Di.invoke(ScopeBlockService).id.should eq(1)
        end
      end
    end

    it "restores outer scope map entry when same-name inner scope exits" do
      Di.scope(:req) do
        Di.provide { ScopeBlockService.new(1) }

        Di.scope(:req) do
          Di.provide { ScopeShutdownService.new(2) }
        end

        # Outer :req scope should still be accessible for health checks
        Di.scopes[:req]?.should_not be_nil
        Di.invoke(ScopeBlockService).id.should eq(1)
      end

      Di.scopes[:req]?.should be_nil
    end
  end

  describe "shutdown" do
    it "calls shutdown on scope-local services" do
      shutdown_svc = ScopeShutdownService.new(1)

      Di.scope(:test) do
        Di.provide { shutdown_svc }
        # Resolve to create the cached instance
        Di.invoke(ScopeShutdownService)
      end

      shutdown_svc.shutdown_called?.should be_true
    end

    it "does not shutdown parent services" do
      parent_svc = ScopeShutdownService.new(1)

      Di.provide { parent_svc }

      Di.scope(:test) do
        # Do nothing, just create and exit scope
      end

      parent_svc.shutdown_called?.should be_false
    end
  end

  describe "cleanup on exception" do
    it "cleans up scope even when block raises" do
      Di.provide { ScopeParentService.new }

      begin
        Di.scope(:test) do
          Di.provide { ScopeBlockService.new(42) }
          raise "Test error"
        end
      rescue
        # Expected
      end

      Di.current_scope.should be_nil
      Di.registry.registered?("ScopeBlockService").should be_false
    end

    it "cleans up scope state even when service shutdown raises" do
      Di.provide { ScopeParentService.new }

      error = expect_raises(Di::ShutdownError) do
        Di.scope(:req) do
          Di.provide { ScopeFailShutdown.new }
          Di.invoke(ScopeFailShutdown)
        end
      end

      error.errors.size.should eq(1)
      Di.current_scope.should be_nil
      Di.scopes[:req]?.should be_nil
    end

    it "preserves body exception when both body and shutdown fail" do
      error = expect_raises(Exception, "body error") do
        Di.scope(:dual_fail) do
          Di.provide { ScopeFailShutdown.new }
          Di.invoke(ScopeFailShutdown)
          raise "body error"
        end
      end

      error.message.should eq("body error")
      error.should_not be_a(Di::ShutdownError)
      Di.current_scope.should be_nil
    end
  end
end

private class ScopeFailShutdown
  def shutdown
    raise "scope shutdown failed"
  end
end
