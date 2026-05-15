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
# Cache behavior is provided by the `Cacheable` concern. The backing store
# defaults to `Rails.cache` but can be injected via the constructor, which
# makes the orchestrator easy to test in isolation.
#
# Failures bubble up as typed exceptions (subclasses of
# `ApplicationService::Error`) so the controller can rescue them in one place.
class ForecastFetcher < ApplicationService
  include Cacheable

  class CoordinatesUnavailableError < NotFoundError; end

  cache_namespace "forecasts"
  cache_ttl 30.minutes

  COORD_PRECISION = 2 # ≈1.1km grid

  attr_reader :query, :unit_system

  def initialize(address:, unit_system: "imperial", cache_store: nil)
    @query = address
    @unit_system = unit_system.presence_in(%w[imperial metric]) || "imperial"
    self.cache_store = cache_store if cache_store
  end

  def call
    address = GeocodingService.call(query)
    identifier = location_identifier(address)
    raise CoordinatesUnavailableError, missing_location_message if identifier.nil?

    served_from_cache = cached?(unit_system, identifier)

    entry = fetch_cached(unit_system, identifier) do
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
      entry[:payload],
      address: address,
      unit_system: unit_system,
      retrieved_at: entry[:retrieved_at],
      from_cache: served_from_cache
    )
  end

  private

  def location_identifier(address)
    address&.zip_code.presence || coord_bucket(address)
  end

  def coord_bucket(address)
    return nil unless address&.coordinates?

    "geo:#{address.latitude.round(COORD_PRECISION)},#{address.longitude.round(COORD_PRECISION)}"
  end

  def missing_location_message
    "We couldn't determine the coordinates for that address. Please try a different one."
  end
end
