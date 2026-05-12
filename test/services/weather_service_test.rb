require "test_helper"

class WeatherServiceTest < ActiveSupport::TestCase
  test "returns the raw Open-Meteo response as an indifferent hash" do
    body = {
      "timezone" => "America/Los_Angeles",
      "current" => { "temperature_2m" => 71.4, "weather_code" => 2 },
      "daily"   => { "time" => ["2026-05-09"] }
    }.to_json

    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    payload = WeatherService.call(latitude: 37.42, longitude: -122.08, unit_system: "imperial")

    assert_equal "America/Los_Angeles", payload[:timezone]
    assert_equal "America/Los_Angeles", payload["timezone"]
    assert_equal 71.4, payload[:current][:temperature_2m]
  end

  test "raises ArgumentError when coordinates are missing" do
    error = assert_raises(ArgumentError) { WeatherService.call(latitude: nil, longitude: nil) }
    assert_match(/latitude/i, error.message)
  end

  test "raises ProviderError on a non-200 response" do
    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 503, body: "")

    error = assert_raises(ApplicationService::ProviderError) do
      WeatherService.call(latitude: 1.0, longitude: 1.0)
    end
    assert_match(/503/, error.message)
  end

  test "raises NetworkError when the request times out" do
    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast}).to_timeout

    assert_raises(ApplicationService::NetworkError) do
      WeatherService.call(latitude: 1.0, longitude: 1.0)
    end
  end
end
