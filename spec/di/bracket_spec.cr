require "../spec_helper"

private class BracketService
  getter id : Int32

  def initialize(@id = 0)
  end
end

private class BracketTransient
  getter counter : Int32

  def initialize(@counter = 0)
  end
end

private class NamedBracketDb
  getter url : String

  def initialize(@url : String)
  end
end

describe "Di[]" do
  describe "with registered service" do
    it "returns the resolved instance" do
      Di.provide { BracketService.new(42) }

      result = Di[BracketService]
      result.should be_a(BracketService)
      result.id.should eq(42)
    end

    it "returns the same instance for singleton providers" do
      Di.provide { BracketService.new(rand(1000) + 1) }

      instance1 = Di[BracketService]
      instance2 = Di[BracketService]

      instance1.should eq(instance2)
    end

    it "returns new instances for transient providers" do
      Di.provide(transient: true) { BracketTransient.new(rand(1000) + 1) }

      instance1 = Di[BracketTransient]
      instance2 = Di[BracketTransient]

      instance1.should_not eq(instance2)
    end

    it "raises ServiceNotFound for unregistered type" do
      expect_raises(Di::ServiceNotFound, "Service not registered: BracketService") do
        Di[BracketService]
      end
    end
  end

  describe "type safety" do
    it "returns exactly T, not Object" do
      Di.provide { BracketService.new(99) }

      result = Di[BracketService]
      typeof(result).should eq(BracketService)
    end
  end

  describe "with named provider" do
    it "resolves a named provider" do
      Di.provide(as: :primary) { NamedBracketDb.new("postgres://primary") }

      db = Di[NamedBracketDb, :primary]
      db.should be_a(NamedBracketDb)
      db.url.should eq("postgres://primary")
    end

    it "resolves different instances for different names" do
      Di.provide(as: :primary) { NamedBracketDb.new("postgres://primary") }
      Di.provide(as: :replica) { NamedBracketDb.new("postgres://replica") }

      primary = Di[NamedBracketDb, :primary]
      replica = Di[NamedBracketDb, :replica]

      primary.url.should eq("postgres://primary")
      replica.url.should eq("postgres://replica")
    end

    it "raises ServiceNotFound for unknown name" do
      expect_raises(Di::ServiceNotFound, "Service not registered: NamedBracketDb/unknown") do
        Di[NamedBracketDb, :unknown]
      end
    end
  end
end

describe "Di[]?" do
  describe "with registered service" do
    it "returns the resolved instance" do
      Di.provide { BracketService.new(77) }

      result = Di[BracketService]?
      result.should be_a(BracketService)
      if svc = result
        svc.id.should eq(77)
      end
    end

    it "returns nil for unregistered type" do
      result = Di[BracketService]?
      result.should be_nil
    end
  end

  describe "type safety" do
    it "returns T?, not Object?" do
      Di.provide { BracketService.new(88) }

      result = Di[BracketService]?
      typeof(result).should eq(BracketService?)
    end
  end

  describe "with named provider" do
    it "resolves a named provider" do
      Di.provide(as: :primary) { NamedBracketDb.new("postgres://primary") }

      db = Di[NamedBracketDb, :primary]?
      db.should be_a(NamedBracketDb)
      if d = db
        d.url.should eq("postgres://primary")
      end
    end

    it "returns nil for unknown name" do
      result = Di[NamedBracketDb, :unknown]?
      result.should be_nil
    end
  end
end

# Compile-time guard: Di[Type, non_literal] and Di[Type, non_literal]? raise
# at macro expansion time with:
#   "Di[] name requires a Symbol literal, got ... (use :name not a variable)"
#   "Di[]? name requires a Symbol literal, got ... (use :name not a variable)"
#
# These cannot be tested with spec expectations because the error occurs during
# compilation, not at runtime. The compile-time guards are in src/di.cr.

describe "Di[] vs Di.invoke equivalence" do
  it "both return the same singleton instance" do
    Di.provide { BracketService.new(123) }

    via_bracket = Di[BracketService]
    via_invoke = Di.invoke(BracketService)

    via_bracket.should eq(via_invoke)
    via_bracket.id.should eq(123)
  end

  it "both raise ServiceNotFound for unregistered type" do
    bracket_raised = false
    invoke_raised = false

    begin
      Di[BracketService]
    rescue Di::ServiceNotFound
      bracket_raised = true
    end

    begin
      Di.invoke(BracketService)
    rescue Di::ServiceNotFound
      invoke_raised = true
    end

    bracket_raised.should be_true
    invoke_raised.should be_true
  end
end

describe "Di[]? vs Di.invoke? equivalence" do
  it "both return nil for unregistered type" do
    Di[BracketService]?.should be_nil
    Di.invoke?(BracketService).should be_nil
  end

  it "both return the same singleton instance" do
    Di.provide { BracketService.new(456) }

    via_bracket = Di[BracketService]?
    via_invoke = Di.invoke?(BracketService)

    via_bracket.should eq(via_invoke)
    if svc = via_bracket
      svc.id.should eq(456)
    end
  end
end
