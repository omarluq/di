require "../spec_helper"

private class CircularA
  def initialize(@b : CircularB)
  end
end

private class CircularB
  def initialize(@a : CircularA)
  end
end

private class CircularDeepA
  def initialize(@b : CircularDeepB)
  end
end

private class CircularDeepB
  def initialize(@c : CircularDeepC)
  end
end

private class CircularDeepC
  def initialize(@a : CircularDeepA)
  end
end

private class TransientA
  def initialize(@b : TransientB)
  end
end

private class TransientB
  def initialize(@a : TransientA)
  end
end

private class NamedNonCyclic
  getter source : String

  def initialize(@source : String)
  end
end

describe "Circular dependency detection" do
  it "detects A -> B -> A cycle" do
    Di.provide { CircularA.new(Di.invoke(CircularB)) }
    Di.provide { CircularB.new(Di.invoke(CircularA)) }

    expect_raises(Di::CircularDependency, /Circular dependency detected/) do
      Di.invoke(CircularA)
    end
  end

  it "detects deep cycle A -> B -> C -> A" do
    Di.provide { CircularDeepA.new(Di.invoke(CircularDeepB)) }
    Di.provide { CircularDeepB.new(Di.invoke(CircularDeepC)) }
    Di.provide { CircularDeepC.new(Di.invoke(CircularDeepA)) }

    expect_raises(Di::CircularDependency, /Circular dependency detected/) do
      Di.invoke(CircularDeepA)
    end
  end

  it "includes the full chain in the error" do
    Di.provide { CircularA.new(Di.invoke(CircularB)) }
    Di.provide { CircularB.new(Di.invoke(CircularA)) }

    begin
      Di.invoke(CircularA)
    rescue ex : Di::CircularDependency
      ex.chain.first.should eq("CircularA")
      ex.chain.last.should eq("CircularA")
      ex.chain.size.should be >= 2
    end
  end

  it "detects cycle in transient providers" do
    Di.provide(transient: true) { TransientA.new(Di.invoke(TransientB)) }
    Di.provide(transient: true) { TransientB.new(Di.invoke(TransientA)) }

    expect_raises(Di::CircularDependency, /Circular dependency detected/) do
      Di.invoke(TransientA)
    end
  end

  it "allows same-type named providers in non-cyclic chain" do
    Di.provide(as: :a) { NamedNonCyclic.new("a") }
    Di.provide(as: :b) { NamedNonCyclic.new("b") }

    a = Di.invoke(NamedNonCyclic, :a)
    b = Di.invoke(NamedNonCyclic, :b)

    a.source.should eq("a")
    b.source.should eq("b")
  end
end
