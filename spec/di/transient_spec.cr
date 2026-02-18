require "../spec_helper"

private class TransientService
  getter id : Int32

  def initialize(@id : Int32)
  end
end

describe "Di.provide with transient option" do
  it "registers a transient provider" do
    Di.provide(transient: true) { TransientService.new(1) }

    provider = Di.registry.get("TransientService")
    provider.transient?.should be_true
  end

  it "defaults to singleton (not transient)" do
    Di.provide { TransientService.new(1) }

    provider = Di.registry.get("TransientService")
    provider.transient?.should be_false
  end

  it "creates new instance on each invoke for transient" do
    Di.provide(transient: true) { TransientService.new(rand(1000) + 1) }

    instance1 = Di.invoke(TransientService)
    instance2 = Di.invoke(TransientService)

    instance1.should_not eq(instance2)
  end

  it "returns same instance for singleton" do
    Di.provide { TransientService.new(1) }

    instance1 = Di.invoke(TransientService)
    instance2 = Di.invoke(TransientService)

    instance1.should eq(instance2)
  end
end

describe "Di.provide with named + transient" do
  it "combines as: and transient: arguments" do
    Di.provide(as: :replica, transient: true) { TransientService.new(rand(1000) + 1) }

    provider = Di.registry.get("TransientService/replica")
    provider.transient?.should be_true

    instance1 = Di.invoke(TransientService, :replica)
    instance2 = Di.invoke(TransientService, :replica)

    instance1.should_not eq(instance2)
  end

  it "allows different transient settings for different names" do
    Di.provide(as: :singleton) { TransientService.new(1) }
    Di.provide(as: :transient, transient: true) { TransientService.new(rand(1000) + 1) }

    singleton_provider = Di.registry.get("TransientService/singleton")
    transient_provider = Di.registry.get("TransientService/transient")

    singleton_provider.transient?.should be_false
    transient_provider.transient?.should be_true
  end
end
