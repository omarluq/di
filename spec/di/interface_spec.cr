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
end
