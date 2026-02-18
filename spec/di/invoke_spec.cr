require "../spec_helper"

private class InvokeTestService
  getter id : Int32

  def initialize(@id = 0)
  end
end

private class TransientService
  getter counter : Int32

  def initialize(@counter = 0)
  end
end

describe "Di.invoke" do
  describe "with registered service" do
    it "returns the resolved instance" do
      Di.provide { InvokeTestService.new(42) }

      result = Di.invoke(InvokeTestService)
      result.should be_a(InvokeTestService)
      result.id.should eq(42)
    end

    it "returns the same instance for singleton providers" do
      Di.provide { InvokeTestService.new(rand(1000) + 1) }

      instance1 = Di.invoke(InvokeTestService)
      instance2 = Di.invoke(InvokeTestService)

      instance1.should eq(instance2)
    end

    it "returns new instances for transient providers" do
      Di.provide(transient: true) { TransientService.new(rand(1000) + 1) }

      instance1 = Di.invoke(TransientService)
      instance2 = Di.invoke(TransientService)

      instance1.should_not eq(instance2)
    end

    it "raises ServiceNotFound for unregistered type" do
      expect_raises(Di::ServiceNotFound, "Service not registered: InvokeTestService") do
        Di.invoke(InvokeTestService)
      end
    end
  end

  describe "type safety" do
    it "returns exactly T, not Object" do
      Di.provide { InvokeTestService.new(99) }

      result = Di.invoke(InvokeTestService)
      typeof(result).should eq(InvokeTestService)
    end
  end
end

describe "Di.invoke?" do
  describe "with registered service" do
    it "returns the resolved instance" do
      Di.provide { InvokeTestService.new(77) }

      result = Di.invoke?(InvokeTestService)
      result.should be_a(InvokeTestService)
      if svc = result
        svc.id.should eq(77)
      end
    end

    it "returns nil for unregistered type" do
      result = Di.invoke?(InvokeTestService)
      result.should be_nil
    end
  end

  describe "type safety" do
    it "returns T?, not Object?" do
      Di.provide { InvokeTestService.new(88) }

      result = Di.invoke?(InvokeTestService)
      typeof(result).should eq(InvokeTestService?)
    end
  end
end
