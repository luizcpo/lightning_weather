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

  # Custom writers ensure nested hashes are always exposed as
  # ActiveSupport::HashWithIndifferentAccess so consumers don't need to
  # care whether the keys came from a fresh API response (string keys)
  # or from a cached Ruby hash (symbol keys).
  def current=(value)
    super(indifferent(value))
  end

  def daily=(value)
    super(Array(value).map { |entry| indifferent(entry) })
  end

  # Factory: build a Forecast from a raw Open-Meteo /v1/forecast payload.
  # Keeping the parsing logic on the model means the WeatherService can stay
  # focused on I/O and any caller (tests, console, jobs) can construct a
  # Forecast directly from a payload without going through the service.
  def self.from_open_meteo(payload, address:, unit_system: "imperial", retrieved_at: Time.current, from_cache: false)
    payload = payload.with_indifferent_access

    new(
      formatted_address: address&.formatted_address,
      zip_code:          address&.zip_code,
      latitude:          address&.latitude,
      longitude:         address&.longitude,
      unit_system:       unit_system,
      timezone:          payload[:timezone],
      retrieved_at:      retrieved_at,
      from_cache:        from_cache,
      current:           parse_current(payload[:current] || {}),
      daily:             parse_daily(payload[:daily] || {})
    )
  end

  def self.parse_current(raw)
    {
      temperature:  raw[:temperature_2m]&.to_f&.round(1),
      feels_like:   raw[:apparent_temperature]&.to_f&.round(1),
      humidity:     raw[:relative_humidity_2m]&.to_f&.round,
      wind_speed:   raw[:wind_speed_10m]&.to_f&.round(1),
      weather_code: raw[:weather_code]&.to_i,
      observed_at:  raw[:time]
    }
  end
  private_class_method :parse_current

  def self.parse_daily(raw)
    Array(raw[:time]).each_with_index.map do |date, index|
      {
        date:                      date,
        weather_code:              raw[:weather_code]&.at(index)&.to_i,
        temperature_max:           raw[:temperature_2m_max]&.at(index)&.to_f&.round(1),
        temperature_min:           raw[:temperature_2m_min]&.at(index)&.to_f&.round(1),
        sunrise:                   raw[:sunrise]&.at(index),
        sunset:                    raw[:sunset]&.at(index),
        precipitation_probability: raw[:precipitation_probability_max]&.at(index)&.to_i
      }
    end
  end
  private_class_method :parse_daily

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
    current&.dig(:temperature)
  end

  def current_feels_like
    current&.dig(:feels_like)
  end

  def current_humidity
    current&.dig(:humidity)
  end

  def current_wind_speed
    current&.dig(:wind_speed)
  end

  def current_weather_code
    current&.dig(:weather_code)
  end

  def today
    daily_forecasts.first
  end

  def daily_forecasts
    Array(daily)
  end

  private

  def indifferent(value)
    value.is_a?(Hash) ? value.with_indifferent_access : value
  end
end
