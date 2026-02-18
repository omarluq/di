require "../spec_helper"

private class ResetTestService
  def initialize
  end
end

describe "Di.reset!" do
  it "clears all registered providers" do
    Di.provide { ResetTestService.new }
    Di.registry.size.should eq(1)

    Di.reset!
    Di.registry.size.should eq(0)
  end

  it "clears registration order" do
    Di.provide { ResetTestService.new }
    Di.registry.order.size.should eq(1)

    Di.reset!
    Di.registry.order.should be_empty
  end

  it "allows re-registration after reset" do
    Di.provide { ResetTestService.new }
    Di.reset!

    Di.provide { ResetTestService.new }
    Di.registry.registered?("ResetTestService").should be_true
  end

  it "raises ScopeError when called inside an active scope" do
    Di.provide { ResetTestService.new }

    expect_raises(Di::ScopeError, /inside an active scope/) do
      Di.scope(:test) do
        Di.reset!
      end
    end
  end
end
