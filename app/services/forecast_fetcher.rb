# Orchestrates the forecast lookup pipeline:
#
#   1. Geocode the user-provided address (or trust client-provided coords).
#   2. Use the resulting ZIP code as the cache key for the forecast.
#   3. On cache miss, fetch the weather forecast from WeatherService.
#   4. Build a Forecast presenter that knows whether it came from cache.
#
# Caching is intentionally keyed by ZIP code (not the raw address) so that
# different addresses within the same ZIP share a single cached payload.
class ForecastFetcher < ApplicationService
  CACHE_TTL = 30.minutes
  CACHE_NAMESPACE = "forecasts".freeze

  attr_reader :address, :unit_system

  def initialize(address:, unit_system: "imperial")
    @address = address
    @unit_system = unit_system.presence_in(%w[imperial metric]) || "imperial"
  end

  def call
    geocode_result = GeocodingService.call(address)
    return geocode_result if geocode_result.failure?

    location = geocode_result.value
    zip_code = location[:zip_code]

    return Result.failure(missing_zip_message) if zip_code.blank?

    served_from_cache = Rails.cache.exist?(cache_key(zip_code))

    forecast_payload = Rails.cache.fetch(cache_key(zip_code), expires_in: CACHE_TTL) do
      weather_result = WeatherService.call(
        latitude: location[:latitude],
        longitude: location[:longitude],
        unit_system: unit_system
      )
      return weather_result if weather_result.failure?

      weather_result.value.merge(
        formatted_address: location[:formatted_address],
        zip_code: zip_code,
        latitude: location[:latitude],
        longitude: location[:longitude]
      )
    end

    Result.success(build_forecast(forecast_payload, served_from_cache))
  end

  private

  def cache_key(zip_code)
    [CACHE_NAMESPACE, unit_system, zip_code].join(":")
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

  def missing_zip_message
    "We couldn't determine a ZIP/postal code for that address. " \
      "Please pick a more specific suggestion."
  end
end
