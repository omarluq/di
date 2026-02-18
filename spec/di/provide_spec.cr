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
end
