require "../spec_helper"

private class RegTestService
  getter id : Int32

  def initialize(@id = 0)
  end
end

describe Di::Registry do
  describe "#register and #get" do
    it "round-trips a provider" do
      registry = Di::Registry.new
      provider = Di::Provider::Instance(RegTestService).new(-> { RegTestService.new(1) })
      registry.register("RegTestService", provider)

      result = registry.get("RegTestService")
      result.should eq(provider)
    end

    it "raises AlreadyRegistered on duplicate key" do
      registry = Di::Registry.new
      provider1 = Di::Provider::Instance(RegTestService).new(-> { RegTestService.new(1) })
      provider2 = Di::Provider::Instance(RegTestService).new(-> { RegTestService.new(2) })

      registry.register("RegTestService", provider1)
      expect_raises(Di::AlreadyRegistered, "Service already registered: RegTestService") do
        registry.register("RegTestService", provider2)
      end
    end

    it "raises ServiceNotFound for unknown key" do
      registry = Di::Registry.new
      expect_raises(Di::ServiceNotFound, "Service not registered: Missing") do
        registry.get("Missing")
      end
    end

    it "parses named keys in error messages" do
      registry = Di::Registry.new
      expect_raises(Di::ServiceNotFound, "Service not registered: Database/primary") do
        registry.get("Database/primary")
      end
    end
  end

  describe "#get?" do
    it "returns provider when registered" do
      registry = Di::Registry.new
      provider = Di::Provider::Instance(RegTestService).new(-> { RegTestService.new })
      registry.register("RegTestService", provider)

      registry.get?("RegTestService").should eq(provider)
    end

    it "returns nil when not registered" do
      registry = Di::Registry.new
      registry.get?("Missing").should be_nil
    end
  end

  describe "#registered?" do
    it "returns true for registered key" do
      registry = Di::Registry.new
      registry.register("RegTestService", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))
      registry.registered?("RegTestService").should be_true
    end

    it "returns false for unregistered key" do
      registry = Di::Registry.new
      registry.registered?("Missing").should be_false
    end
  end

  describe "#clear" do
    it "removes all providers and resets order" do
      registry = Di::Registry.new
      registry.register("A", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))
      registry.register("B", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))

      registry.size.should eq(2)
      registry.order.size.should eq(2)

      registry.clear
      registry.size.should eq(0)
      registry.order.size.should eq(0)
    end
  end

  describe "#order and #reverse_order" do
    it "tracks registration order" do
      registry = Di::Registry.new
      registry.register("First", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))
      registry.register("Second", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))
      registry.register("Third", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))

      registry.order.should eq(["First", "Second", "Third"])
      registry.reverse_order.should eq(["Third", "Second", "First"])
    end
  end

  describe "#size" do
    it "returns the number of registered providers" do
      registry = Di::Registry.new
      registry.size.should eq(0)

      registry.register("A", Di::Provider::Instance(RegTestService).new(-> { RegTestService.new }))
      registry.size.should eq(1)
    end
  end

  describe ".key" do
    it "returns type name for unnamed" do
      Di::Registry.key("Database").should eq("Database")
    end

    it "returns type/name for named" do
      Di::Registry.key("Database", "primary").should eq("Database/primary")
    end
  end
end
