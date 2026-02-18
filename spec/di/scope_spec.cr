require "../spec_helper"

private class ScopeTestService
  getter id : Int32

  def initialize(@id = 0)
  end
end

private class ScopeRequestService
  getter name : String

  def initialize(@name = "request")
  end
end

describe Di::Scope do
  describe "#register and #get" do
    it "round-trips a provider" do
      scope = Di::Scope.new(:root)
      provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) })
      scope.register("ScopeTestService", provider)

      scope.get("ScopeTestService").should eq(provider)
    end

    it "raises AlreadyRegistered on duplicate key" do
      scope = Di::Scope.new(:root)
      provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      scope.register("ScopeTestService", provider)

      expect_raises(Di::AlreadyRegistered, "Service already registered: ScopeTestService") do
        scope.register("ScopeTestService", provider)
      end
    end
  end

  describe "parent inheritance" do
    it "inherits providers from parent" do
      parent = Di::Scope.new(:root)
      parent.register("ScopeTestService", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) }))

      child = Di::Scope.new(:request, parent: parent)

      child.get?("ScopeTestService").should_not be_nil
      child.registered?("ScopeTestService").should be_true
    end

    it "does not show parent providers in local scope" do
      parent = Di::Scope.new(:root)
      parent.register("ScopeTestService", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) }))

      child = Di::Scope.new(:request, parent: parent)

      child.local?("ScopeTestService").should be_false
      child.size.should eq(0)
    end

    it "shadows parent provider with local override" do
      parent = Di::Scope.new(:root)
      parent_provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) })
      parent.register("ScopeTestService", parent_provider)

      child = Di::Scope.new(:request, parent: parent)
      child_provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(2) })
      child.register("ScopeTestService", child_provider)

      child.get("ScopeTestService").should eq(child_provider)
      parent.get("ScopeTestService").should eq(parent_provider)
    end

    it "does not affect parent when registering in child" do
      parent = Di::Scope.new(:root)
      child = Di::Scope.new(:request, parent: parent)

      child.register("ScopeRequestService", Di::Provider::Instance(ScopeRequestService).new(-> { ScopeRequestService.new }))

      child.registered?("ScopeRequestService").should be_true
      parent.registered?("ScopeRequestService").should be_false
    end
  end

  describe "nested scopes" do
    it "chains through multiple parent scopes" do
      root = Di::Scope.new(:root)
      root.register("ScopeTestService", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) }))

      request = Di::Scope.new(:request, parent: root)
      request.register("ScopeRequestService", Di::Provider::Instance(ScopeRequestService).new(-> { ScopeRequestService.new }))

      transaction = Di::Scope.new(:transaction, parent: request)

      transaction.registered?("ScopeTestService").should be_true
      transaction.registered?("ScopeRequestService").should be_true
    end
  end

  describe "#clear" do
    it "clears local providers without affecting parent" do
      parent = Di::Scope.new(:root)
      parent.register("ScopeTestService", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      child = Di::Scope.new(:request, parent: parent)
      child.register("ScopeRequestService", Di::Provider::Instance(ScopeRequestService).new(-> { ScopeRequestService.new }))

      child.clear
      child.size.should eq(0)
      child.registered?("ScopeTestService").should be_true
      parent.size.should eq(1)
    end
  end

  describe "#order and #reverse_order" do
    it "tracks local registration order" do
      scope = Di::Scope.new(:root)
      scope.register("A", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))
      scope.register("B", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      scope.order.should eq(["A", "B"])
      scope.reverse_order.should eq(["B", "A"])
    end
  end
end
