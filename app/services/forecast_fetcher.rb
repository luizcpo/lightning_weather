# Orchestrates the forecast lookup pipeline:
#
#   1. Geocode the user-provided query into an `Address` model.
#   2. Build a cache key from the ZIP code when available, otherwise from a
#      coarse coordinate bucket (~1km) so city-level queries still benefit
#      from caching.
#   3. On cache miss, fetch the raw weather payload from `WeatherService`
#      and store it together with the retrieval timestamp.
#   4. Return a `Forecast` model assembled by `Forecast.from_open_meteo`.
#
# Failures bubble up as typed exceptions (subclasses of
# `ApplicationService::Error`) so the controller can rescue them in one place.
class ForecastFetcher < ApplicationService
  class CoordinatesUnavailableError < NotFoundError; end

  CACHE_TTL = 30.minutes
  CACHE_NAMESPACE = "forecasts".freeze
  COORD_PRECISION = 2 # ≈1.1km grid

  attr_reader :query, :unit_system

  def initialize(address:, unit_system: "imperial")
    @query = address
    @unit_system = unit_system.presence_in(%w[imperial metric]) || "imperial"
  end

  def call
    address = GeocodingService.call(query)
    cache_key = build_cache_key(address)
    raise CoordinatesUnavailableError, missing_location_message if cache_key.nil?

    served_from_cache = Rails.cache.exist?(cache_key)

    cached_entry = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      {
        payload: WeatherService.call(
          latitude: address.latitude,
          longitude: address.longitude,
          unit_system: unit_system
        ),
        retrieved_at: Time.current
      }
    end

    Forecast.from_open_meteo(
      cached_entry[:payload],
      address: address,
      unit_system: unit_system,
      retrieved_at: cached_entry[:retrieved_at],
      from_cache: served_from_cache
    )
  end

  private

  def build_cache_key(address)
    identifier = address&.zip_code.presence || coord_bucket(address)
    return nil if identifier.blank?

    [CACHE_NAMESPACE, unit_system, identifier].join(":")
  end

  def coord_bucket(address)
    return nil unless address&.coordinates?

    "geo:#{address.latitude.round(COORD_PRECISION)},#{address.longitude.round(COORD_PRECISION)}"
  end

  def missing_location_message
    "We couldn't determine the coordinates for that address. Please try a different one."
  end
end
