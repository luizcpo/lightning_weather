class Forecast
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :formatted_address, :string
  attribute :zip_code, :string
  attribute :latitude, :float
  attribute :longitude, :float
  attribute :unit_system, :string, default: "imperial"
  attribute :timezone, :string
  attribute :retrieved_at, :datetime
  attribute :from_cache, :boolean, default: false
  attribute :current
  attribute :daily, default: -> { [] }

  def from_cache?
    from_cache == true
  end

  def temperature_unit
    imperial? ? "°F" : "°C"
  end

  def speed_unit
    imperial? ? "mph" : "km/h"
  end

  def imperial?
    unit_system.to_s == "imperial"
  end

  def current_temperature
    current&.dig(:temperature) || current&.dig("temperature")
  end

  def current_feels_like
    current&.dig(:feels_like) || current&.dig("feels_like")
  end

  def current_humidity
    current&.dig(:humidity) || current&.dig("humidity")
  end

  def current_wind_speed
    current&.dig(:wind_speed) || current&.dig("wind_speed")
  end

  def current_weather_code
    current&.dig(:weather_code) || current&.dig("weather_code")
  end

  def today
    daily_forecasts.first
  end

  def daily_forecasts
    Array(daily).map { |entry| entry.transform_keys(&:to_sym) }
  end

  def to_h
    {
      formatted_address: formatted_address,
      zip_code: zip_code,
      latitude: latitude,
      longitude: longitude,
      unit_system: unit_system,
      timezone: timezone,
      retrieved_at: retrieved_at,
      current: current,
      daily: daily
    }
  end
end
