require "../spec_helper"

private class ConcurrencyService
  getter scope_id : String

  def initialize(@scope_id : String)
  end
end

private class SlowServiceA
  def initialize
    Fiber.yield
  end
end

private class SlowServiceB
  def initialize
    Fiber.yield
  end
end

private class SingletonCounter
  @@count = 0

  def self.reset
    @@count = 0
  end

  def self.count
    @@count
  end

  def initialize
    @@count += 1
    Fiber.yield
  end
end

describe "Fiber isolation" do
  describe "scope context" do
    it "isolates scopes across concurrent fibers" do
      results = Channel({String, String}).new(2)

      spawn do
        Di.scope(:a) do
          Di.provide { ConcurrencyService.new("a") }
          Fiber.yield
          svc = Di.invoke(ConcurrencyService)
          results.send({:a.to_s, svc.scope_id})
        end
      end

      spawn do
        Di.scope(:b) do
          Di.provide { ConcurrencyService.new("b") }
          Fiber.yield
          svc = Di.invoke(ConcurrencyService)
          results.send({:b.to_s, svc.scope_id})
        end
      end

      result_a = results.receive
      result_b = results.receive

      {result_a, result_b}.should contain({"a", "a"})
      {result_a, result_b}.should contain({"b", "b"})
    end

    it "isolates same-name scopes across concurrent fibers" do
      results = Channel({String, String}).new(2)

      spawn do
        Di.scope(:req) do
          Di.provide { ConcurrencyService.new("fiber1") }
          Fiber.yield
          svc = Di.invoke(ConcurrencyService)
          results.send({"fiber1", svc.scope_id})
        end
      end

      spawn do
        Di.scope(:req) do
          Di.provide { ConcurrencyService.new("fiber2") }
          Fiber.yield
          svc = Di.invoke(ConcurrencyService)
          results.send({"fiber2", svc.scope_id})
        end
      end

      r1 = results.receive
      r2 = results.receive

      {r1, r2}.should contain({"fiber1", "fiber1"})
      {r1, r2}.should contain({"fiber2", "fiber2"})
    end
  end

  describe "fiber-local cleanup" do
    it "removes fiber state after last scope exits" do
      before_count = TestHelpers.fiber_state_count
      mid_count = Channel(Int32).new
      done = Channel(Nil).new

      spawn do
        Di.scope(:temp) do
          Di.provide { ConcurrencyService.new("cleanup") }
          Di.invoke(ConcurrencyService)
          mid_count.send(TestHelpers.fiber_state_count)
        end
        done.send(nil)
      end

      mid_count.receive.should be > before_count
      done.receive
      TestHelpers.fiber_state_count.should eq(before_count)
    end
  end

  describe "resolution chain" do
    it "does not falsely detect cycles across concurrent resolves" do
      Di.provide { SlowServiceA.new }
      Di.provide { SlowServiceB.new }

      errors = Channel(Exception?).new(2)

      spawn do
        begin
          Di.invoke(SlowServiceA)
          errors.send(nil)
        rescue ex
          errors.send(ex)
        end
      end

      spawn do
        begin
          Di.invoke(SlowServiceB)
          errors.send(nil)
        rescue ex
          errors.send(ex)
        end
      end

      err_a = errors.receive
      err_b = errors.receive

      err_a.should be_nil
      err_b.should be_nil
    end
  end

  describe "global scope guard" do
    it "blocks reset! while scope active in another fiber" do
      ready = Channel(Nil).new
      done = Channel(Exception?).new

      spawn do
        Di.scope(:cross_fiber) do
          ready.send(nil)
          Fiber.yield
          # Hold scope open
          sleep 10.milliseconds
        end
        done.send(nil)
      rescue ex
        done.send(ex)
      end

      ready.receive # Wait for scope to be active

      expect_raises(Di::ScopeError, /while scopes are active/) do
        Di.reset!
      end

      done.receive.should be_nil
    end

    it "blocks shutdown! while scope active in another fiber" do
      ready = Channel(Nil).new
      done = Channel(Exception?).new

      Di.provide { ConcurrencyService.new("test") }

      spawn do
        Di.scope(:cross_fiber_shutdown) do
          ready.send(nil)
          Fiber.yield
          sleep 10.milliseconds
        end
        done.send(nil)
      rescue ex
        done.send(ex)
      end

      ready.receive

      expect_raises(Di::ScopeError, /while scopes are active/) do
        Di.shutdown!
      end

      done.receive.should be_nil
    end
  end

  describe "invoke-only fibers" do
    it "does not allocate fiber state for Di.invoke without scope" do
      before = TestHelpers.fiber_state_count

      Di.provide { ConcurrencyService.new("test") }
      Di.invoke(ConcurrencyService)

      TestHelpers.fiber_state_count.should eq(before)
    end

    it "does not allocate fiber state for Di.provide without scope" do
      before = TestHelpers.fiber_state_count

      Di.provide { ConcurrencyService.new("new_svc") }

      TestHelpers.fiber_state_count.should eq(before)
    end
  end

  describe "singleton thread safety" do
    it "constructs singleton only once under concurrent invoke" do
      SingletonCounter.reset
      Di.provide { SingletonCounter.new }

      results = Channel(SingletonCounter).new(5)
      5.times do
        spawn { results.send(Di.invoke(SingletonCounter)) }
      end

      instances = 5.times.map { results.receive }.to_a
      instances.uniq!.size.should eq(1)
      SingletonCounter.count.should eq(1)
    end
  end
end
