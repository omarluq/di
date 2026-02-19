require "../spec_helper"

private class HealthyService
  property? healthy : Bool = true

  def initialize(@healthy = true)
  end

  def healthy? : Bool
    @healthy
  end
end

private class UnhealthyService
  def initialize
  end

  def healthy? : Bool
    false
  end
end

private class NoHealthService
  def initialize
  end
end

private class ExplodingHealthService
  def initialize
  end

  def healthy? : Bool
    raise "probe failure"
  end
end

# Service that calls Di.invoke during health check (tests recursive-lock safety).
private class DependentHealthService
  def healthy? : Bool
    # This would deadlock if health check held registry/scope mutex.
    Di.invoke(HealthyService).healthy?
  end
end

private class HealthyDependency
  def healthy? : Bool
    true
  end
end

describe "Di.healthy?" do
  describe "root scope" do
    it "returns health for services that implement healthy?" do
      Di.provide { HealthyService.new }
      Di.provide { UnhealthyService.new }
      Di.invoke(HealthyService)
      Di.invoke(UnhealthyService)

      result = Di.healthy?
      result["HealthyService"].should be_true
      result["UnhealthyService"].should be_false
    end

    it "skips services without healthy?" do
      Di.provide { NoHealthService.new }
      Di.invoke(NoHealthService)

      result = Di.healthy?
      result.has_key?("NoHealthService").should be_false
    end

    it "skips unresolved singletons" do
      Di.provide { HealthyService.new }
      # Never invoke — no instance to check.

      result = Di.healthy?
      result.has_key?("HealthyService").should be_false
    end

    it "returns empty hash when no services registered" do
      Di.healthy?.should be_empty
    end

    it "returns false when health probe raises" do
      Di.provide { ExplodingHealthService.new }
      Di.invoke(ExplodingHealthService)

      result = Di.healthy?
      result["ExplodingHealthService"].should be_false
    end
  end

  describe "named scope" do
    it "returns health for scope-local services" do
      Di.scope(:request) do
        Di.provide { HealthyService.new }
        Di.invoke(HealthyService)

        result = Di.healthy?(:request)
        result["HealthyService"].should be_true
      end
    end

    it "includes inherited parent services" do
      Di.provide { HealthyService.new }
      Di.invoke(HealthyService)

      Di.scope(:request) do
        Di.provide { UnhealthyService.new }
        Di.invoke(UnhealthyService)

        result = Di.healthy?(:request)
        result["HealthyService"].should be_true
        result["UnhealthyService"].should be_false
      end
    end

    it "raises ScopeNotFound for unknown scope" do
      expect_raises(Di::ScopeNotFound, "Scope not found: unknown") do
        Di.healthy?(:unknown)
      end
    end

    it "allows healthy? to call Di.invoke without deadlock" do
      Di.scope(:req) do
        Di.provide { HealthyService.new }
        Di.provide { DependentHealthService.new }
        Di.invoke(HealthyService)
        Di.invoke(DependentHealthService)

        result = Di.healthy?(:req)
        result["DependentHealthService"].should be_true
      end
    end
  end

  describe "re-entrant health probes" do
    it "allows root healthy? when probe calls Di.invoke" do
      Di.provide { HealthyService.new }
      Di.provide { DependentHealthService.new }
      Di.invoke(HealthyService)
      Di.invoke(DependentHealthService)

      result = Di.healthy?
      result["HealthyService"].should be_true
      result["DependentHealthService"].should be_true
    end
  end
end
