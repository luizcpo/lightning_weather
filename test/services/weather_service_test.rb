require "test_helper"

class WeatherServiceTest < ActiveSupport::TestCase
  test "fetches and normalises Open-Meteo response" do
    body = {
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
        "sunset" => ["2026-05-09T20:00", "2026-05-10T20:00"],
        "precipitation_probability_max" => [10, 80]
      }
    }.to_json

    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = WeatherService.call(latitude: 37.42, longitude: -122.08, unit_system: "imperial")

    assert_predicate result, :success?
    assert_equal "America/Los_Angeles", result.value[:timezone]
    assert_equal 71.4, result.value[:current][:temperature]
    assert_equal 2, result.value[:daily].size
    assert_equal 75.1, result.value[:daily].first[:temperature_max]
    assert_equal 80, result.value[:daily].last[:precipitation_probability]
  end

  test "returns failure when coordinates are missing" do
    result = WeatherService.call(latitude: nil, longitude: nil)

    assert_predicate result, :failure?
    assert_match(/coordinates/i, result.error)
  end

  test "wraps non-200 HTTP responses" do
    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 503, body: "")

    result = WeatherService.call(latitude: 1.0, longitude: 1.0)

    assert_predicate result, :failure?
    assert_match(/503/, result.error)
  end
end
