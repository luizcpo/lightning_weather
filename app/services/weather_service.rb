require "faraday"
require "faraday/retry"

# Thin HTTP wrapper around Open-Meteo's `/v1/forecast` endpoint.
# The service is responsible only for I/O: it makes the request, validates
# the HTTP response and raises a typed error on failure. Translating the
# JSON payload into a domain object is the responsibility of `Forecast`
# (see `Forecast.from_open_meteo`).
class WeatherService < ApplicationService
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

  def initialize(latitude:, longitude:, unit_system: "imperial")
    @latitude = latitude
    @longitude = longitude
    @unit_system = unit_system
  end

  def call
    raise ArgumentError, "Latitude and longitude are required." if latitude.blank? || longitude.blank?

    response = http_client.get(OPEN_METEO_URL, query_params)
    raise ProviderError, "Weather provider returned status #{response.status}." unless response.success?

    body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    body.with_indifferent_access
  rescue Faraday::Error => error
    raise NetworkError, "Network error while contacting weather provider: #{error.message}"
  rescue JSON::ParserError
    raise ProviderError, "Weather provider returned an invalid JSON response."
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

  def http_client
    @http_client ||= Faraday.new do |conn|
      conn.request :retry, max: 2, interval: 0.2,
                           exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
      conn.response :json, content_type: /\bjson$/
      conn.options.timeout = 5
      conn.options.open_timeout = 3
    end
  end
end
