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
end
