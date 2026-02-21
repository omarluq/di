require "../spec_helper"

describe Di::ServiceNotFound do
  it "formats message for unnamed service" do
    err = Di::ServiceNotFound.new("Database")
    err.message.should eq("Service not registered: Database")
    err.type_name.should eq("Database")
    err.service_name.should be_nil
  end

  it "formats message for named service" do
    err = Di::ServiceNotFound.new("Database", "primary")
    err.message.should eq("Service not registered: Database:primary")
    err.type_name.should eq("Database")
    err.service_name.should eq("primary")
  end
end

describe Di::CircularDependency do
  it "formats chain in message" do
    err = Di::CircularDependency.new(["A", "B", "A"])
    err.message.should eq("Circular dependency detected: A -> B -> A")
    err.chain.should eq(["A", "B", "A"])
  end
end

describe Di::AlreadyRegistered do
  it "formats message for unnamed service" do
    err = Di::AlreadyRegistered.new("Database")
    err.message.should eq("Service already registered: Database")
    err.type_name.should eq("Database")
    err.service_name.should be_nil
  end

  it "formats message for named service" do
    err = Di::AlreadyRegistered.new("Database", "primary")
    err.message.should eq("Service already registered: Database:primary")
    err.type_name.should eq("Database")
    err.service_name.should eq("primary")
  end
end

describe Di::ScopeNotFound do
  it "includes scope name in message" do
    err = Di::ScopeNotFound.new("request")
    err.message.should eq("Scope not found: request")
    err.scope_name.should eq("request")
  end
end
