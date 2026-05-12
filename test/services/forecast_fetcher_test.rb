require "test_helper"

class ForecastFetcherTest < ActiveSupport::TestCase
  GEOCODE_RESPONSE = {
    "status" => "OK",
    "results" => [
      {
        "formatted_address" => "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
        "geometry" => { "location" => { "lat" => 37.42, "lng" => -122.08 } },
        "address_components" => [
          { "long_name" => "94043",         "short_name" => "94043",         "types" => ["postal_code"] },
          { "long_name" => "Mountain View", "short_name" => "Mountain View", "types" => ["locality"] },
          { "long_name" => "United States", "short_name" => "US",            "types" => ["country"] }
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
      "sunset"  => ["2026-05-09T20:00"],
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
    forecast = ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")

    assert_instance_of Forecast, forecast
    assert_equal "94043", forecast.zip_code
    assert_equal 70.0,    forecast.current_temperature
    refute forecast.from_cache?
  end

  test "subsequent calls within the TTL are served from cache" do
    ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")
    second = ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")

    assert second.from_cache?, "Expected the second lookup to be served from cache"
    assert_requested :get, %r{api\.open-meteo\.com/v1/forecast}, times: 1
  end

  test "different addresses sharing the same ZIP share the cached payload" do
    ForecastFetcher.call(address: "1600 Amphitheatre Pkwy")
    other = ForecastFetcher.call(address: "1601 Different Street")

    assert other.from_cache?, "Different address with same ZIP should hit the same cache key"
    assert_requested :get, %r{api\.open-meteo\.com/v1/forecast}, times: 1
  end

  test "city-level queries succeed by falling back to a coordinate bucket" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "Berlin, Germany",
          "geometry" => { "location" => { "lat" => 52.520008, "lng" => 13.404954 } },
          "address_components" => [
            { "long_name" => "Berlin", "short_name" => "Berlin", "types" => ["locality"] }
          ]
        }
      ]
    }.to_json
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    forecast = ForecastFetcher.call(address: "Berlin")

    assert_nil forecast.zip_code
    assert_equal "Berlin, Germany", forecast.formatted_address
    refute forecast.from_cache?
  end

  test "two city-level queries inside the same ~1km bucket share a cache entry" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "Berlin, Germany",
          "geometry" => { "location" => { "lat" => 52.5201, "lng" => 13.4051 } },
          "address_components" => [
            { "long_name" => "Berlin", "short_name" => "Berlin", "types" => ["locality"] }
          ]
        }
      ]
    }.to_json
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    ForecastFetcher.call(address: "Berlin")
    second = ForecastFetcher.call(address: "Berlin, Germany")

    assert second.from_cache?
    assert_requested :get, %r{api\.open-meteo\.com/v1/forecast}, times: 1
  end

  test "raises CoordinatesUnavailableError when geocoder returns no coordinates" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "Nowhere",
          "geometry" => { "location" => {} },
          "address_components" => []
        }
      ]
    }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    error = assert_raises(ForecastFetcher::CoordinatesUnavailableError) do
      ForecastFetcher.call(address: "???")
    end
    assert_match(/coordinates/i, error.message)
  end

  test "propagates geocoder failures (e.g. AddressNotFound)" do
    body = { "status" => "ZERO_RESULTS", "results" => [] }.to_json
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    assert_raises(GeocodingService::AddressNotFoundError) do
      ForecastFetcher.call(address: "asdfghjkl")
    end
  end
end
