require "test_helper"

class ForecastTest < ActiveSupport::TestCase
  OPEN_METEO_PAYLOAD = {
    "timezone" => "America/Los_Angeles",
    "current" => {
      "time" => "2026-05-09T18:00",
      "temperature_2m" => 71.4,
      "apparent_temperature" => 70.9,
      "relative_humidity_2m" => 55,
      "wind_speed_10m" => 8.7,
      "weather_code" => 2
    },
    "daily" => {
      "time" => ["2026-05-09", "2026-05-10"],
      "weather_code" => [2, 61],
      "temperature_2m_max" => [75.1, 68.4],
      "temperature_2m_min" => [55.2, 51.0],
      "sunrise" => ["2026-05-09T06:00", "2026-05-10T06:00"],
      "sunset"  => ["2026-05-09T20:00", "2026-05-10T20:00"],
      "precipitation_probability_max" => [10, 80]
    }
  }.freeze

  setup do
    @address = Address.new(
      formatted_address: "Mountain View, CA",
      zip_code: "94043",
      latitude: 37.42,
      longitude: -122.08
    )
  end

  test ".from_open_meteo parses every metric and timezone" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address)

    assert_equal "America/Los_Angeles", forecast.timezone
    assert_equal 71.4,                  forecast.current_temperature
    assert_equal 70.9,                  forecast.current_feels_like
    assert_equal 55,                    forecast.current_humidity
    assert_equal 8.7,                   forecast.current_wind_speed
    assert_equal 2,                     forecast.current_weather_code
  end

  test ".from_open_meteo builds the daily forecast in order" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address)

    assert_equal 2, forecast.daily_forecasts.size
    assert_equal 75.1, forecast.daily_forecasts.first[:temperature_max]
    assert_equal 80,   forecast.daily_forecasts.last[:precipitation_probability]
  end

  test ".from_open_meteo copies address attributes onto the forecast" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address)

    assert_equal "Mountain View, CA", forecast.formatted_address
    assert_equal "94043",             forecast.zip_code
    assert_equal 37.42,               forecast.latitude
  end

  test ".from_open_meteo accepts symbol-keyed payloads (e.g. coming from cache)" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD.deep_symbolize_keys, address: @address)

    assert_equal 71.4, forecast.current_temperature
    assert_equal 2,    forecast.daily_forecasts.size
  end

  test "current and daily entries are accessible by both string and symbol keys" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address)

    assert_equal 71.4, forecast.current[:temperature]
    assert_equal 71.4, forecast.current["temperature"]
    assert_equal 75.1, forecast.daily_forecasts.first[:temperature_max]
    assert_equal 75.1, forecast.daily_forecasts.first["temperature_max"]
  end

  test "#temperature_unit and #speed_unit follow the unit_system" do
    imperial = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address, unit_system: "imperial")
    metric   = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address, unit_system: "metric")

    assert_equal "°F",   imperial.temperature_unit
    assert_equal "mph",  imperial.speed_unit
    assert_equal "°C",   metric.temperature_unit
    assert_equal "km/h", metric.speed_unit
  end

  test "#from_cache? defaults to false" do
    forecast = Forecast.from_open_meteo(OPEN_METEO_PAYLOAD, address: @address)
    refute forecast.from_cache?
  end
end
