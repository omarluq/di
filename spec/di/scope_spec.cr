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

  describe "#delete" do
    it "removes a provider from the scope" do
      scope = Di::Scope.new(:root)
      provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      scope.register("ScopeTestService", provider)
      scope.size.should eq(1)

      scope.delete("ScopeTestService")
      scope.size.should eq(0)
      scope.order.should eq([] of String)
    end

    it "does not affect parent when deleting from child" do
      parent = Di::Scope.new(:root)
      parent.register("ScopeTestService", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      child = Di::Scope.new(:request, parent: parent)
      child.delete("ScopeTestService") # No-op in child, doesn't raise

      parent.registered?("ScopeTestService").should be_true
    end
  end

  describe "#each" do
    it "iterates over local providers" do
      scope = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) })
      p2 = Di::Provider::Instance(ScopeRequestService).new(-> { ScopeRequestService.new })
      scope.register("A", p1)
      scope.register("B", p2)

      keys = [] of String
      providers = [] of Di::Provider::Base
      scope.each { |k, v| keys << k; providers << v }

      keys.should eq(["A", "B"])
      providers.should eq([p1, p2])
    end
  end

  describe "#snapshot" do
    it "returns a copy of local providers" do
      scope = Di::Scope.new(:root)
      provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      scope.register("ScopeTestService", provider)

      snap = scope.snapshot
      snap.should eq({"ScopeTestService" => provider})
      snap.size.should eq(1)

      # Modifying snapshot doesn't affect scope
      snap.clear
      scope.size.should eq(1)
    end
  end

  describe "#get" do
    it "raises ServiceNotFound when key not in scope chain" do
      scope = Di::Scope.new(:root)

      expect_raises(Di::ServiceNotFound, "Service not registered: MissingService") do
        scope.get("MissingService")
      end
    end
  end

  describe "fallback_registry" do
    it "inherits providers from fallback registry" do
      registry = Di::Registry.new
      provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) })
      registry.register("ScopeTestService", provider)

      scope = Di::Scope.new(:request, fallback_registry: registry)

      scope.get?("ScopeTestService").should eq(provider)
      scope.registered?("ScopeTestService").should be_true
    end

    it "shadows fallback registry with local override" do
      registry = Di::Registry.new
      registry_provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(1) })
      registry.register("ScopeTestService", registry_provider)

      scope = Di::Scope.new(:request, fallback_registry: registry)
      scope_provider = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new(2) })
      scope.register("ScopeTestService", scope_provider)

      scope.get("ScopeTestService").should eq(scope_provider)
      registry.get("ScopeTestService").should eq(registry_provider)
    end
  end

  describe "interface methods" do
    it "#count_implementations returns total across scope chain" do
      parent = Di::Scope.new(:root)
      parent.register("~Iface:ImplA", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      child = Di::Scope.new(:request, parent: parent)
      child.register("~Iface:ImplB", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      child.count_implementations("Iface").should eq(2)
      parent.count_implementations("Iface").should eq(1)
    end

    it "#implementation_names returns names across scope chain" do
      parent = Di::Scope.new(:root)
      parent.register("~Iface:ImplA", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      child = Di::Scope.new(:request, parent: parent)
      child.register("~Iface:ImplB:primary", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      names = child.implementation_names("Iface")
      names.should contain("ImplA")
      names.should contain("ImplB:primary")
    end

    it "#get_all returns all interface providers" do
      parent = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      parent.register("~Iface:ImplA", p1)

      child = Di::Scope.new(:request, parent: parent)
      p2 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      child.register("~Iface:ImplB", p2)

      all = child.get_all("Iface")
      all.size.should eq(2)
      all.should contain(p1)
      all.should contain(p2)
    end

    it "#get_all_keyed returns keyed hash for deduplication" do
      parent = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      parent.register("~Iface:ImplA", p1)

      child = Di::Scope.new(:request, parent: parent)
      p2 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      child.register("~Iface:ImplB", p2)

      keyed = child.get_all_keyed("Iface")
      keyed.should eq({"~Iface:ImplA" => p1, "~Iface:ImplB" => p2})
    end

    it "#find_all_by_name returns empty when no matches in chain" do
      scope = Di::Scope.new(:root)
      scope.find_all_by_name("Iface", "missing").should eq([] of Di::Provider::Base)
    end

    it "#find_by_name raises ServiceNotFound when no matches" do
      scope = Di::Scope.new(:root)
      expect_raises(Di::ServiceNotFound) do
        scope.find_by_name("Iface", "missing")
      end
    end

    it "#find_by_name raises on ambiguous matches" do
      scope = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      p2 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      scope.register("~Iface:ImplA:shared", p1)
      scope.register("~Iface:ImplB:shared", p2)

      expect_raises(Di::AmbiguousServiceError, /Iface has 2 implementations/) do
        scope.find_by_name("Iface", "shared")
      end
    end

    it "#find_all_by_name_keyed falls back to ancestor when no local matches" do
      parent = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      parent.register("~Iface:ImplA:primary", p1)

      child = Di::Scope.new(:request, parent: parent)
      # No local matches for "primary" — should fall back to parent
      keyed = child.find_all_by_name_keyed("Iface", "primary")
      keyed.should eq({"~Iface:ImplA:primary" => p1})
    end

    it "#find_all_by_name_keyed returns local only when present" do
      parent = Di::Scope.new(:root)
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      parent.register("~Iface:ImplA:primary", p1)

      child = Di::Scope.new(:request, parent: parent)
      p2 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      child.register("~Iface:ImplB:primary", p2)

      # Child has local match, so parent is not consulted
      keyed = child.find_all_by_name_keyed("Iface", "primary")
      keyed.should eq({"~Iface:ImplB:primary" => p2})
    end
  end

  describe "interface methods with fallback_registry" do
    it "#find_all_by_name delegates to fallback_registry" do
      registry = Di::Registry.new
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      registry.register("~Iface:ImplA:primary", p1)

      scope = Di::Scope.new(:request, fallback_registry: registry)
      matches = scope.find_all_by_name("Iface", "primary")
      matches.size.should eq(1)
      matches.should contain(p1)
    end

    it "#get_all merges with fallback_registry" do
      registry = Di::Registry.new
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      registry.register("~Iface:ImplA", p1)

      scope = Di::Scope.new(:request, fallback_registry: registry)
      p2 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      scope.register("~Iface:ImplB", p2)

      all = scope.get_all("Iface")
      all.size.should eq(2)
      all.should contain(p1)
      all.should contain(p2)
    end

    it "#get_all_keyed merges with fallback_registry" do
      registry = Di::Registry.new
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      registry.register("~Iface:ImplA", p1)

      scope = Di::Scope.new(:request, fallback_registry: registry)
      keyed = scope.get_all_keyed("Iface")
      keyed.should eq({"~Iface:ImplA" => p1})
    end

    it "#find_all_by_name_keyed merges with fallback_registry" do
      registry = Di::Registry.new
      p1 = Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new })
      registry.register("~Iface:ImplA:primary", p1)

      scope = Di::Scope.new(:request, fallback_registry: registry)
      keyed = scope.find_all_by_name_keyed("Iface", "primary")
      keyed.should eq({"~Iface:ImplA:primary" => p1})
    end

    it "#registered? checks fallback_registry" do
      registry = Di::Registry.new
      registry.register("~Iface:ImplA", Di::Provider::Instance(ScopeTestService).new(-> { ScopeTestService.new }))

      scope = Di::Scope.new(:request, fallback_registry: registry)
      scope.registered?("~Iface:ImplA").should be_true
      scope.registered?("NonExistent").should be_false
    end
  end
end
