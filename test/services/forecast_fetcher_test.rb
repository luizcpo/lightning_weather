require "test_helper"

class ForecastFetcherTest < ActiveSupport::TestCase
  GEOCODE_RESPONSE = {
    "status" => "OK",
    "results" => [
      {
        "formatted_address" => "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
        "geometry" => { "location" => { "lat" => 37.42, "lng" => -122.08 } },
        "address_components" => [
          { "long_name" => "94043", "short_name" => "94043", "types" => ["postal_code"] },
          { "long_name" => "Mountain View", "short_name" => "Mountain View", "types" => ["locality"] },
          { "long_name" => "United States", "short_name" => "US", "types" => ["country"] }
        ]
      }
    ]
  }.to_json

  WEATHER_RESPONSE = {
    "timezone" => "America/Los_Angeles",
    "current" => {
      "time" => "2026-05-09T18:00",
      "temperature_2m" => 70.0,
      "apparent_temperature" => 69.0,
      "relative_humidity_2m" => 50,
      "wind_speed_10m" => 5.0,
      "weather_code" => 1
    },
    "daily" => {
      "time" => ["2026-05-09"],
      "weather_code" => [1],
      "temperature_2m_max" => [75.0],
      "temperature_2m_min" => [55.0],
      "sunrise" => ["2026-05-09T06:00"],
      "sunset" => ["2026-05-09T20:00"],
      "precipitation_probability_max" => [0]
    }
  }.to_json

  setup do
    Rails.application.config.x.google_maps_api_key = "test-key"

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: GEOCODE_RESPONSE, headers: { "Content-Type" => "application/json" })

    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 200, body: WEATHER_RESPONSE, headers: { "Content-Type" => "application/json" })
  end

  test "first call hits the network and reports a fresh result" do
    result = ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")

    assert_predicate result, :success?
    forecast = result.value
    assert_equal "94043", forecast.zip_code
    assert_equal 70.0, forecast.current_temperature
    refute forecast.from_cache?
  end

  test "subsequent calls within the TTL are served from cache" do
    ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")
    second = ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")

    assert_predicate second, :success?
    assert second.value.from_cache?, "Expected the second lookup to be served from cache"

    assert_requested :get, %r{api\.open-meteo\.com/v1/forecast}, times: 1
  end

  test "different addresses sharing the same ZIP share the cached payload" do
    ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")
    other = ForecastFetcher.call(address: "1601 Different Street")

    assert_predicate other, :success?
    assert other.value.from_cache?, "Different address with same ZIP should hit the same cache key"
    assert_requested :get, %r{api\.open-meteo\.com/v1/forecast}, times: 1
  end

  test "fails clearly when ZIP code cannot be determined" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "Pacific Ocean",
          "geometry" => { "location" => { "lat" => 0, "lng" => 0 } },
          "address_components" => [
            { "long_name" => "Earth", "short_name" => "Earth", "types" => ["country"] }
          ]
        }
      ]
    }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = ForecastFetcher.call(address: "Middle of the ocean")

    assert_predicate result, :failure?
    assert_match(/ZIP/i, result.error)
  end
end
