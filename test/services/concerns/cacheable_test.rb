require "test_helper"

class CacheableTest < ActiveSupport::TestCase
  class CounterService
    include Cacheable

    cache_namespace "counter_test"
    cache_ttl 5.minutes

    attr_reader :calls

    def initialize(cache_store: nil)
      @calls = 0
      self.cache_store = cache_store if cache_store
    end

    def increment(key)
      send(:fetch_cached, key) { @calls += 1; @calls }
    end

    def already_cached?(key)
      send(:cached?, key)
    end

    def key_for(*parts)
      send(:cache_key_for, *parts)
    end
  end

  setup do
    @store = ActiveSupport::Cache::MemoryStore.new
    @service = CounterService.new(cache_store: @store)
  end

  test "fetch_cached computes on miss and reads from cache on hit" do
    assert_equal 1, @service.increment("a")
    assert_equal 1, @service.increment("a"), "second call should hit cache"
    assert_equal 1, @service.calls,           "block should have run only once"
  end

  test "cached? reflects current cache state" do
    refute @service.already_cached?("b")
    @service.increment("b")
    assert @service.already_cached?("b")
  end

  test "cache_key_for namespaces every key under cache_namespace" do
    assert_equal "counter_test:foo:bar", @service.key_for("foo", "bar")
  end

  test "cache_store defaults to Rails.cache when not injected" do
    assert_equal Rails.cache, CounterService.new.cache_store
  end

  test "the injected store can be swapped without affecting the default" do
    other_store = ActiveSupport::Cache::MemoryStore.new
    other = CounterService.new(cache_store: other_store)

    other.increment("shared")
    refute @service.already_cached?("shared"),
           "stores must be isolated when injected separately"
  end
end
