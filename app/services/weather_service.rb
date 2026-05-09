require "faraday"
require "faraday/retry"

# Fetches a weather forecast (current + daily) for given coordinates.
#
# Open-Meteo is used because it's free, reliable, and doesn't require an API
# key. See https://open-meteo.com/en/docs for the schema.
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
    return Result.failure("Coordinates are required.") if latitude.blank? || longitude.blank?

    response = http_client.get(OPEN_METEO_URL, query_params)

    unless response.success?
      return Result.failure("Weather provider returned status #{response.status}.")
    end

    body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)

    Result.success(parse_payload(body))
  rescue Faraday::Error => e
    Result.failure("Network error while contacting weather provider: #{e.message}.")
  rescue JSON::ParserError
    Result.failure("Invalid response from weather provider.")
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

  def parse_payload(body)
    current = body["current"] || {}
    daily = body["daily"] || {}

    {
      retrieved_at: Time.current,
      timezone: body["timezone"],
      unit_system: unit_system,
      current: {
        temperature: current["temperature_2m"]&.to_f&.round(1),
        feels_like: current["apparent_temperature"]&.to_f&.round(1),
        humidity: current["relative_humidity_2m"]&.to_f&.round,
        wind_speed: current["wind_speed_10m"]&.to_f&.round(1),
        weather_code: current["weather_code"]&.to_i,
        observed_at: current["time"]
      },
      daily: build_daily_forecast(daily)
    }
  end

  def build_daily_forecast(daily)
    times = Array(daily["time"])

    times.each_with_index.map do |date_string, index|
      {
        date: date_string,
        weather_code: daily.dig("weather_code", index)&.to_i,
        temperature_max: daily.dig("temperature_2m_max", index)&.to_f&.round(1),
        temperature_min: daily.dig("temperature_2m_min", index)&.to_f&.round(1),
        sunrise: daily.dig("sunrise", index),
        sunset: daily.dig("sunset", index),
        precipitation_probability: daily.dig("precipitation_probability_max", index)&.to_i
      }
    end
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
