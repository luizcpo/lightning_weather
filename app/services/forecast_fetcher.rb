# Orchestrates the forecast lookup pipeline:
#
#   1. Geocode the user-provided address.
#   2. Build a cache key from the ZIP code when Google returns one,
#      otherwise from the rounded latitude/longitude (so city-level queries
#      like "Berlin" or "Tokyo" still benefit from caching).
#   3. On cache miss, fetch the weather forecast from WeatherService.
#   4. Build a Forecast presenter that knows whether it came from cache.
#
# Caching is intentionally keyed by ZIP code (not the raw address) so that
# different addresses within the same ZIP share a single cached payload.
# When no ZIP is available we fall back to a coarse "geo bucket" — coordinates
# rounded to ~1km — so queries that resolve to the same area still share a
# single cache entry.
class ForecastFetcher < ApplicationService
  CACHE_TTL = 30.minutes
  CACHE_NAMESPACE = "forecasts".freeze
  COORD_PRECISION = 2 # ≈1.1km grid

  attr_reader :address, :unit_system

  def initialize(address:, unit_system: "imperial")
    @address = address
    @unit_system = unit_system.presence_in(%w[imperial metric]) || "imperial"
  end

  def call
    geocode_result = GeocodingService.call(address)
    return geocode_result if geocode_result.failure?

    location = geocode_result.value
    cache_key = build_cache_key(location)
    return Result.failure(missing_location_message) if cache_key.nil?

    served_from_cache = Rails.cache.exist?(cache_key)

    forecast_payload = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      weather_result = WeatherService.call(
        latitude: location[:latitude],
        longitude: location[:longitude],
        unit_system: unit_system
      )
      return weather_result if weather_result.failure?

      weather_result.value.merge(
        formatted_address: location[:formatted_address],
        zip_code: location[:zip_code],
        latitude: location[:latitude],
        longitude: location[:longitude]
      )
    end

    Result.success(build_forecast(forecast_payload, served_from_cache))
  end

  private

  def build_cache_key(location)
    identifier = location[:zip_code].presence || coord_bucket(location)
    return nil if identifier.blank?

    [CACHE_NAMESPACE, unit_system, identifier].join(":")
  end

  def coord_bucket(location)
    lat = location[:latitude]
    lng = location[:longitude]
    return nil if lat.nil? || lng.nil?

    "geo:#{lat.round(COORD_PRECISION)},#{lng.round(COORD_PRECISION)}"
  end

  def build_forecast(payload, from_cache)
    Forecast.new(
      formatted_address: payload[:formatted_address],
      zip_code: payload[:zip_code],
      latitude: payload[:latitude],
      longitude: payload[:longitude],
      unit_system: payload[:unit_system] || unit_system,
      timezone: payload[:timezone],
      retrieved_at: payload[:retrieved_at],
      current: payload[:current],
      daily: payload[:daily],
      from_cache: from_cache
    )
  end

  def missing_location_message
    "We couldn't determine the coordinates for that address. Please try a different one."
  end
end
