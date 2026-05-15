# Adds a small, opinionated caching API to service objects.
#
# What it gives you:
#
#   * A `cache_store` that defaults to `Rails.cache` and is injectable
#     via the constructor or `#cache_store=`. This makes services
#     trivially testable with a custom `ActiveSupport::Cache::MemoryStore`
#     and lets us swap to Solid Cache / Redis without changing services.
#   * Class-level macros to declare cache configuration:
#       cache_namespace "forecasts"
#       cache_ttl 30.minutes
#   * Instance helpers `fetch_cached`, `cached?`, and `cache_key_for` that
#     namespace every key under the class's `cache_namespace`, preventing
#     collisions across services that share the same backend.
#
# Example:
#
#   class ForecastFetcher < ApplicationService
#     include Cacheable
#
#     cache_namespace "forecasts"
#     cache_ttl 30.minutes
#
#     def call
#       fetch_cached(unit_system, zip_code) { expensive_lookup }
#     end
#   end
module Cacheable
  extend ActiveSupport::Concern

  DEFAULT_TTL = 1.hour

  class_methods do
    # `cache_namespace "forecasts"` to set, `cache_namespace` to read.
    def cache_namespace(name = nil)
      @cache_namespace = name.to_s if name
      @cache_namespace ||= self.name
    end

    # `cache_ttl 30.minutes` to set, `cache_ttl` to read.
    def cache_ttl(duration = nil)
      @cache_ttl = duration if duration
      @cache_ttl ||= DEFAULT_TTL
    end
  end

  attr_writer :cache_store

  def cache_store
    @cache_store ||= Rails.cache
  end

  private

  # Fetches a cached value or computes it via `&block` on miss.
  # `key_parts` are joined under the class's `cache_namespace`.
  def fetch_cached(*key_parts, ttl: self.class.cache_ttl, &block)
    cache_store.fetch(cache_key_for(*key_parts), expires_in: ttl, &block)
  end

  # True when an entry for `key_parts` already exists in the cache —
  # useful for telling fresh fetches from cache hits *before* `fetch_cached`
  # wraps a miss with a fresh computation.
  def cached?(*key_parts)
    cache_store.exist?(cache_key_for(*key_parts))
  end

  def cache_key_for(*parts)
    [self.class.cache_namespace, *parts.compact].join(":")
  end
end
