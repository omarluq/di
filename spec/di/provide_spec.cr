require "../spec_helper"

private class ProvideTestService
  getter id : Int32

  def initialize(@id = 0)
  end
end

private class AnotherService
  getter name : String

  def initialize(@name = "default")
  end
end

private class ProvideDepA
  getter id : Int32

  def initialize(@id : Int32)
  end
end

private class ProvideDepB
  getter dep : ProvideDepA

  def initialize(@dep : ProvideDepA)
  end
end

private class ProvideDepC
  getter dep_a : ProvideDepA
  getter dep_b : ProvideDepB

  def initialize(@dep_a : ProvideDepA, @dep_b : ProvideDepB)
  end
end

describe "Di.provide" do
  describe "with explicit block" do
    it "registers a provider for the block's return type" do
      Di.provide { ProvideTestService.new(42) }

      Di.registry.registered?("ProvideTestService").should be_true
    end

    it "stores the provider with correct type" do
      Di.provide { ProvideTestService.new(99) }

      provider = Di.registry.get("ProvideTestService")
      provider.should be_a(Di::Provider::Instance(ProvideTestService))
    end

    it "raises AlreadyRegistered when registering same type twice" do
      Di.provide { ProvideTestService.new(1) }

      expect_raises(Di::AlreadyRegistered, "Service already registered: ProvideTestService") do
        Di.provide { ProvideTestService.new(2) }
      end
    end

    it "can register multiple different types" do
      Di.provide { ProvideTestService.new(1) }
      Di.provide { AnotherService.new("test") }

      Di.registry.size.should eq(2)
      Di.registry.registered?("ProvideTestService").should be_true
      Di.registry.registered?("AnotherService").should be_true
    end

    it "registers in order for shutdown tracking" do
      Di.provide { ProvideTestService.new(1) }
      Di.provide { AnotherService.new("test") }

      Di.registry.order.should eq(["ProvideTestService", "AnotherService"])
    end
  end

  describe "with dependency-typed block args" do
    it "registers by block return type for single dependency argument" do
      Di.provide { ProvideDepA.new(1) }
      Di.provide(ProvideDepA) { |dep_a| ProvideDepB.new(dep_a) }

      Di.registry.registered?("ProvideDepA").should be_true
      Di.registry.registered?("ProvideDepB").should be_true

      resolved = Di.invoke(ProvideDepB)
      resolved.dep.id.should eq(1)
    end

    it "resolves and passes dependencies in order for multiple dependency arguments" do
      Di.provide { ProvideDepA.new(7) }
      Di.provide(ProvideDepA) { |dep_a| ProvideDepB.new(dep_a) }
      Di.provide(ProvideDepA, ProvideDepB) { |dep_a, dep_b| ProvideDepC.new(dep_a, dep_b) }

      resolved = Di.invoke(ProvideDepC)
      resolved.dep_a.id.should eq(7)
      resolved.dep_b.dep.id.should eq(7)
    end
  end
end
