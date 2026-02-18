require "../spec_helper"

private class TestService
  getter id : Int32

  def initialize(@id = 0)
  end
end

describe Di::Provider::Instance do
  describe "#resolve_typed" do
    it "returns the same instance for singleton providers" do
      call_count = 0
      provider = Di::Provider::Instance(TestService).new(
        -> { call_count += 1; TestService.new(call_count) },
        transient: false
      )

      instance1 = provider.resolve_typed
      instance2 = provider.resolve_typed

      instance1.should eq(instance2)
      instance1.id.should eq(1)
      instance2.id.should eq(1)
      call_count.should eq(1)
    end

    it "returns new instances for transient providers" do
      call_count = 0
      provider = Di::Provider::Instance(TestService).new(
        -> { call_count += 1; TestService.new(call_count) },
        transient: true
      )

      instance1 = provider.resolve_typed
      instance2 = provider.resolve_typed

      instance1.should_not eq(instance2)
      instance1.id.should eq(1)
      instance2.id.should eq(2)
      call_count.should eq(2)
    end
  end

  describe "#resolve_typed" do
    it "returns typed result" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new })
      result = provider.resolve_typed
      result.should be_a(TestService)
    end
  end

  describe "#transient?" do
    it "returns false for singleton providers" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new }, transient: false)
      provider.transient?.should be_false
    end

    it "returns true for transient providers" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new }, transient: true)
      provider.transient?.should be_true
    end
  end

  describe "#instance" do
    it "returns nil before first resolve for singleton" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new })
      provider.instance.should be_nil
    end

    it "returns cached instance after resolve for singleton" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new })
      resolved = provider.resolve_typed
      provider.instance.should eq(resolved)
    end

    it "returns nil for transient providers" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new }, transient: true)
      provider.resolve_typed
      provider.instance.should be_nil
    end
  end

  describe "#reset!" do
    it "clears cached instance for singleton" do
      provider = Di::Provider::Instance(TestService).new(-> { TestService.new })
      provider.resolve_typed
      provider.instance.should_not be_nil

      provider.reset!
      provider.instance.should be_nil
    end

    it "creates fresh instance after reset" do
      call_count = 0
      provider = Di::Provider::Instance(TestService).new(
        -> { call_count += 1; TestService.new(call_count) },
        transient: false
      )

      first = provider.resolve_typed
      provider.reset!
      second = provider.resolve_typed

      first.id.should eq(1)
      second.id.should eq(2)
      call_count.should eq(2)
    end
  end
end
