require "../spec_helper"

private class NamedDatabase
  getter url : String

  def initialize(@url : String)
  end
end

describe "Di.provide with named providers" do
  describe "as: argument" do
    it "registers a named provider with type:name key" do
      Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }

      Di.registry.registered?("NamedDatabase:primary").should be_true
      Di.registry.registered?("NamedDatabase").should be_false
    end

    it "allows multiple names for the same type" do
      Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }
      Di.provide(as: :replica) { NamedDatabase.new("postgres://replica") }

      Di.registry.size.should eq(2)
      Di.registry.registered?("NamedDatabase:primary").should be_true
      Di.registry.registered?("NamedDatabase:replica").should be_true
    end

    it "allows both named and unnamed for same type" do
      Di.provide { NamedDatabase.new("postgres://default") }
      Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }

      Di.registry.size.should eq(2)
      Di.registry.registered?("NamedDatabase").should be_true
      Di.registry.registered?("NamedDatabase:primary").should be_true
    end

    it "raises AlreadyRegistered for duplicate name" do
      Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }

      expect_raises(Di::AlreadyRegistered, "Service already registered: NamedDatabase:primary") do
        Di.provide(as: :primary) { NamedDatabase.new("postgres://primary2") }
      end
    end
  end
end

describe "Di.invoke with named providers" do
  it "resolves a named provider" do
    Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }

    db = Di.invoke(NamedDatabase, :primary)
    db.should be_a(NamedDatabase)
    db.url.should eq("postgres://primary")
  end

  it "resolves different instances for different names" do
    Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }
    Di.provide(as: :replica) { NamedDatabase.new("postgres://replica") }

    primary = Di.invoke(NamedDatabase, :primary)
    replica = Di.invoke(NamedDatabase, :replica)

    primary.url.should eq("postgres://primary")
    replica.url.should eq("postgres://replica")
  end

  it "raises ServiceNotFound for unknown name" do
    expect_raises(Di::ServiceNotFound, "Service not registered: NamedDatabase:unknown") do
      Di.invoke(NamedDatabase, :unknown)
    end
  end
end

describe "Di.invoke? with named providers" do
  it "resolves a named provider" do
    Di.provide(as: :primary) { NamedDatabase.new("postgres://primary") }

    db = Di.invoke?(NamedDatabase, :primary)
    db.should be_a(NamedDatabase)
    if d = db
      d.url.should eq("postgres://primary")
    end
  end

  it "returns nil for unknown name" do
    result = Di.invoke?(NamedDatabase, :unknown)
    result.should be_nil
  end
end
