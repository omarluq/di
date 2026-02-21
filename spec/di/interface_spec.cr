require "../spec_helper"

private module Printable
  abstract def print_data : String
end

private class Square
  include Printable

  def print_data : String
    "Square"
  end
end

private class Circle
  include Printable

  def print_data : String
    "Circle"
  end
end

private abstract class Shape
  abstract def area : Float64
end

private class Rect < Shape
  def area : Float64
    10.0
  end
end

private module Connectable
  abstract def connect : String
end

private class PgConn
  include Connectable

  getter host : String

  def initialize(@host : String)
  end

  def connect : String
    "pg://#{@host}"
  end
end

describe "Di.provide interface binding" do
  describe "module interface" do
    it "registers concrete type under module key" do
      Di.provide Printable, Square

      result = Di[Printable]
      result.should be_a(Printable)
      result.should be_a(Square)
      result.print_data.should eq("Square")
    end

    it "returns the static type as the interface" do
      Di.provide Printable, Square

      result = Di[Printable]
      typeof(result).should eq(Printable)
    end

    it "caches singleton like regular providers" do
      Di.provide Printable, Square

      a = Di[Printable]
      b = Di[Printable]
      a.should eq(b)
    end
  end

  describe "abstract class interface" do
    it "registers subclass under abstract class key" do
      Di.provide Shape, Rect

      result = Di[Shape]
      result.should be_a(Rect)
      result.area.should eq(10.0)
    end
  end

  describe "with named providers" do
    it "registers multiple implementations under different names" do
      Di.provide Printable, Square, as: :square
      Di.provide Printable, Circle, as: :circle

      sq = Di[Printable, :square]
      ci = Di[Printable, :circle]

      sq.print_data.should eq("Square")
      ci.print_data.should eq("Circle")
    end
  end

  describe "with transient" do
    it "creates new instances on each resolve" do
      Di.provide Printable, Square, transient: true

      a = Di[Printable]
      b = Di[Printable]
      a.should_not eq(b)
    end

    it "combines named and transient flags" do
      Di.provide Printable, Square, as: :square, transient: true

      a = Di[Printable, :square]
      b = Di[Printable, :square]
      a.should_not eq(b)
      a.print_data.should eq("Square")
    end
  end

  describe "with auto-wired dependencies" do
    it "resolves constructor dependencies for the implementation" do
      Di.provide { "localhost" }
      Di.provide Connectable, PgConn

      result = Di[Connectable]
      result.should be_a(PgConn)
      result.connect.should eq("pg://localhost")
    end
  end

  describe "multi-registration" do
    it "allows multiple implementations for the same interface" do
      Di.provide Printable, Square
      Di.provide Printable, Circle # Should NOT raise

      all = Di[Array(Printable)]
      all.size.should eq(2)
      all.map(&.print_data).should contain("Square")
      all.map(&.print_data).should contain("Circle")
    end

    it "raises AmbiguousServiceError when resolving ambiguous interface" do
      Di.provide Printable, Square
      Di.provide Printable, Circle

      expect_raises(Di::AmbiguousServiceError, /Printable has 2 implementations/) do
        Di[Printable]
      end
    end

    it "resolves single implementation without error" do
      Di.provide Printable, Square
      # Only one impl, should work fine
      result = Di[Printable]
      result.print_data.should eq("Square")
    end

    it "returns empty array when no implementations registered" do
      all = Di[Array(Printable)]
      all.should eq([] of Printable)
    end

    it "Di[Array(T)] returns typed Array(T)" do
      Di.provide Printable, Square
      Di.provide Printable, Circle

      all = Di[Array(Printable)]
      typeof(all).should eq(Array(Printable))
    end

    it "named interface bindings are discoverable by Di[Array(T)]" do
      Di.provide Printable, Square, as: :square
      Di.provide Printable, Circle, as: :circle

      all = Di[Array(Printable)]
      all.size.should eq(2)
      all.map(&.print_data).should contain("Square")
      all.map(&.print_data).should contain("Circle")
    end

    it "named interface bindings are resolvable by name" do
      Di.provide Printable, Square, as: :square
      Di.provide Printable, Circle, as: :circle

      Di[Printable, :square].print_data.should eq("Square")
      Di[Printable, :circle].print_data.should eq("Circle")
    end

    it "scope shadows parent interface impl instead of raising ambiguity" do
      Di.provide Printable, Square

      Di.scope(:test) do
        Di.provide Printable, Square
        result = Di[Printable]
        result.print_data.should eq("Square")
      end
    end

    it "scope shadows parent named interface by alias name" do
      Di.provide Printable, Square, as: :shape

      Di.scope(:test) do
        Di.provide Printable, Circle, as: :shape
        # Child should shadow parent by name, not create ambiguity
        result = Di[Printable, :shape]
        result.print_data.should eq("Circle")
      end
    end

    it "scope can add new impl alongside parent impl" do
      Di.provide Printable, Square

      Di.scope(:test) do
        Di.provide Printable, Circle
        all = Di[Array(Printable)]
        all.size.should eq(2)
        all.map(&.print_data).should contain("Square")
        all.map(&.print_data).should contain("Circle")
      end
    end

    it "named + unnamed interface bindings coexist" do
      Di.provide Printable, Square, as: :square
      Di.provide Printable, Circle # unnamed

      Di[Printable, :square].print_data.should eq("Square")

      all = Di[Array(Printable)]
      all.size.should eq(2)
      all.map(&.print_data).should contain("Square")
      all.map(&.print_data).should contain("Circle")
    end

    it "named and unnamed bindings of same impl type coexist" do
      Di.provide Printable, Square, as: :square
      Di.provide Printable, Square, transient: true

      Di[Printable, :square].print_data.should eq("Square")

      all = Di[Array(Printable)]
      all.size.should eq(2)
    end
  end

  describe "nilable resolution" do
    it "returns nil when interface is not registered" do
      result = Di[Printable]?
      result.should be_nil
    end

    it "returns instance when registered" do
      Di.provide Printable, Square

      result = Di[Printable]?
      result.should be_a(Printable)
    end
  end

  describe "duplicate key detection" do
    it "raises AlreadyRegistered for same impl + same name" do
      Di.provide Printable, Square, as: :primary
      expect_raises(Di::AlreadyRegistered) do
        Di.provide Printable, Square, as: :primary
      end
    end

    it "raises AlreadyRegistered for same impl without name" do
      Di.provide Printable, Square
      expect_raises(Di::AlreadyRegistered) do
        Di.provide Printable, Square
      end
    end
  end

  describe "ambiguous named interface detection" do
    it "raises AmbiguousServiceError when multiple impls share the same name" do
      Di.provide Printable, Square, as: :shared
      Di.provide Printable, Circle, as: :shared

      expect_raises(Di::AmbiguousServiceError, /Printable has 2 implementations/) do
        Di[Printable, :shared]
      end
    end

    it "raises AmbiguousServiceError in nilable variant for duplicate names" do
      Di.provide Printable, Square, as: :shared
      Di.provide Printable, Circle, as: :shared

      expect_raises(Di::AmbiguousServiceError, /Printable has 2 implementations/) do
        Di[Printable, :shared]?
      end
    end
  end

  describe "named concrete isolation" do
    it "does not leak named concrete into unnamed Di[T] resolution" do
      Di.provide(as: :primary) { Square.new }

      # Square:primary exists but Di[Square] (unnamed) should NOT resolve it
      expect_raises(Di::ServiceNotFound) do
        Di[Square]
      end
    end

    it "does not leak named concrete into Di[Array(T)]" do
      Di.provide(as: :primary) { Square.new }

      # Named concrete is NOT an interface binding, should not appear in Array(T)
      Di[Array(Square)].should eq([] of Square)
    end
  end

  describe "concrete vs interface named precedence" do
    it "concrete Type:name wins over ~Type:Impl:name for the same alias" do
      # Register a concrete named provider (Printable:primary via block)
      Di.provide(as: :primary) { Square.new.as(Printable) }

      # Register an interface binding with the same alias (~Printable:Circle:primary)
      Di.provide Printable, Circle, as: :primary

      # Concrete exact key is checked first — should resolve Square, not Circle
      result = Di[Printable, :primary]
      result.should be_a(Square)
      result.print_data.should eq("Square")
    end
  end

  describe "namespaced type key parsing" do
    it "does not split on :: namespace separator" do
      key = Di::Registry.key("NS::Class", name: "primary")
      key.should eq("NS::Class:primary")
    end

    it "builds interface key with namespaced types" do
      key = Di::Registry.key("NS::Iface", impl: "NS::Impl", name: "primary")
      key.should eq("~NS::Iface:NS::Impl:primary")
    end
  end
end
