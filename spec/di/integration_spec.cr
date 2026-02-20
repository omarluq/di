require "../spec_helper"

# Integration spec mirrors the complete example from spec.md.
# Tests the full lifecycle: registration, resolution, scopes, health, and shutdown.

private class IntegDatabase
  getter url : String
  property? healthy : Bool = true
  getter? shutdown_called : Bool = false

  def initialize(@url : String)
  end

  def healthy? : Bool
    @healthy
  end

  def shutdown
    @shutdown_called = true
  end
end

private class IntegCacheService
  def initialize
  end
end

private class IntegUserRepository
  getter db : IntegDatabase

  def initialize(@db : IntegDatabase)
  end
end

private class IntegUserService
  getter repo : IntegUserRepository
  getter cache : IntegCacheService

  def initialize(@repo : IntegUserRepository, @cache : IntegCacheService)
  end

  def find(id : Int32)
    {id: id}
  end
end

private class IntegCurrentUser
  getter token : String

  def self.from_token(token : String)
    new(token)
  end

  def initialize(@token : String)
  end
end

describe "Integration: full lifecycle" do
  describe "root scope registration and resolution" do
    it "registers and resolves named providers" do
      Di.provide(as: :primary) { IntegDatabase.new("primary_url") }
      Di.provide(as: :replica) { IntegDatabase.new("replica_url") }

      primary = Di[IntegDatabase, :primary]
      replica = Di[IntegDatabase, :replica]

      primary.url.should eq("primary_url")
      replica.url.should eq("replica_url")
      primary.should_not eq(replica)
    end

    it "auto-wires dependencies" do
      Di.provide { IntegDatabase.new("auto_wire_db") }
      Di.provide IntegCacheService
      Di.provide IntegUserRepository
      Di.provide IntegUserService

      svc = Di[IntegUserService]
      svc.repo.db.url.should eq("auto_wire_db")
      svc.cache.should be_a(IntegCacheService)
    end
  end

  describe "health check" do
    it "reports health for resolved singletons" do
      healthy_db = IntegDatabase.new("healthy")
      healthy_db.healthy = true
      unhealthy_db = IntegDatabase.new("unhealthy")
      unhealthy_db.healthy = false

      Di.provide(as: :healthy_db) { healthy_db }
      Di.provide(as: :unhealthy_db) { unhealthy_db }

      Di[IntegDatabase, :healthy_db]
      Di[IntegDatabase, :unhealthy_db]

      health = Di.healthy?
      health["IntegDatabase/healthy_db"].should be_true
      health["IntegDatabase/unhealthy_db"].should be_false
    end
  end

  describe "request scope" do
    it "inherits root providers and adds scope-local ones" do
      Di.provide { IntegDatabase.new("root_db") }

      Di.scope(:request) do
        Di.provide { IntegCurrentUser.from_token("tok_abc") }

        current = Di[IntegCurrentUser]
        current.token.should eq("tok_abc")

        # Inherited from root.
        db = Di[IntegDatabase]
        db.url.should eq("root_db")
      end

      # CurrentUser not visible outside scope.
      Di[IntegCurrentUser]?.should be_nil
    end
  end

  describe "shutdown" do
    it "calls shutdown on singletons" do
      db1 = IntegDatabase.new("db1")
      db2 = IntegDatabase.new("db2")

      Di.provide(as: :first) { db1 }
      Di.provide(as: :second) { db2 }

      Di[IntegDatabase, :first]
      Di[IntegDatabase, :second]

      Di.shutdown!

      db1.shutdown_called?.should be_true
      db2.shutdown_called?.should be_true
    end
  end
end
