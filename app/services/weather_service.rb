# Thin HTTP wrapper around Open-Meteo's `/v1/forecast` endpoint.
# The service is responsible only for I/O: it makes the request, validates
# the HTTP response (via the `HttpClient` concern) and raises a typed error
# on failure. Translating the JSON payload into a domain object is the
# responsibility of `Forecast` (see `Forecast.from_open_meteo`).
class WeatherService < ApplicationService
  include HttpClient

  provider_name "Open-Meteo"

  OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast".freeze

  CURRENT_FIELDS = %w[
    temperature_2m
    apparent_temperature
    relative_humidity_2m
    weather_code
    wind_speed_10m
  ].join(",").freeze

  DAILY_FIELDS = %w[
    weather_code
    temperature_2m_max
    temperature_2m_min
    sunrise
    sunset
    precipitation_probability_max
  ].join(",").freeze

  attr_reader :latitude, :longitude, :unit_system

  def initialize(latitude:, longitude:, unit_system: "imperial", http_client: nil)
    @latitude = latitude
    @longitude = longitude
    @unit_system = unit_system
    self.http_client = http_client if http_client
  end

  def call
    raise ArgumentError, "Latitude and longitude are required." if latitude.blank? || longitude.blank?

    http_get(OPEN_METEO_URL, query_params)
  end

  private

  def query_params
    {
      latitude: latitude,
      longitude: longitude,
      current: CURRENT_FIELDS,
      daily: DAILY_FIELDS,
      timezone: "auto",
      temperature_unit: imperial? ? "fahrenheit" : "celsius",
      wind_speed_unit: imperial? ? "mph" : "kmh",
      forecast_days: 7
    }
  end

  def imperial?
    unit_system.to_s == "imperial"
  end
end
