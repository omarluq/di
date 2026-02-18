require "../spec_helper"

# Dependency services
private class AutowireDatabase
  getter url : String

  def initialize(@url : String)
  end
end

private class AutowireCache
  def initialize
  end
end

private class AutowireRepository
  getter db : AutowireDatabase

  def initialize(@db : AutowireDatabase)
  end
end

private class AutowireService
  getter repo : AutowireRepository
  getter cache : AutowireCache

  def initialize(@repo : AutowireRepository, @cache : AutowireCache)
  end
end

private class NoDepsService
  getter value : Int32

  def initialize
    @value = 42
  end
end

describe "Di.provide auto-wire" do
  describe "with dependencies" do
    it "resolves dependencies from container" do
      Di.provide { AutowireDatabase.new("postgres://localhost") }
      Di.provide { AutowireCache.new }
      Di.provide AutowireRepository

      repo = Di.invoke(AutowireRepository)
      repo.should be_a(AutowireRepository)
      repo.db.url.should eq("postgres://localhost")
    end

    it "resolves transitive dependencies" do
      Di.provide { AutowireDatabase.new("postgres://localhost") }
      Di.provide { AutowireCache.new }
      Di.provide AutowireRepository
      Di.provide AutowireService

      service = Di.invoke(AutowireService)
      service.should be_a(AutowireService)
      service.repo.should be_a(AutowireRepository)
      service.cache.should be_a(AutowireCache)
    end
  end

  describe "without dependencies" do
    it "registers service with no-arg initialize" do
      Di.provide NoDepsService

      svc = Di.invoke(NoDepsService)
      svc.should be_a(NoDepsService)
      svc.value.should eq(42)
    end
  end

  describe "with transient option" do
    it "creates new instance on each invoke" do
      Di.provide NoDepsService, transient: true

      instance1 = Di.invoke(NoDepsService)
      instance2 = Di.invoke(NoDepsService)

      instance1.should_not eq(instance2)
    end
  end

  describe "with named option" do
    it "registers with name" do
      Di.provide { AutowireDatabase.new("postgres://primary") }
      Di.provide { AutowireCache.new }
      Di.provide AutowireRepository, as: :primary

      repo = Di.invoke(AutowireRepository, :primary)
      repo.db.url.should eq("postgres://primary")
    end
  end
end
