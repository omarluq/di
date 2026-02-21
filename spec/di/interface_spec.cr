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

  describe "atomic registration" do
    it "does not leak interface entry when named key conflicts" do
      Di.provide Printable, Square, as: :primary
      # Same name, different impl — named key fails fast, interface never committed
      expect_raises(Di::AlreadyRegistered) do
        Di.provide Printable, Circle, as: :primary
      end
      all = Di[Array(Printable)]
      all.size.should eq(1)
      all.first.print_data.should eq("Square")
    end

    it "rolls back named key when interface key conflicts" do
      Di.provide Printable, Square, as: :s1
      # Same impl, different name — named key succeeds, interface key conflicts, rollback
      expect_raises(Di::AlreadyRegistered) do
        Di.provide Printable, Square, as: :s2
      end
      # Named key should have been rolled back
      result = Di[Printable, :s2]?
      result.should be_nil
    end
  end
end
