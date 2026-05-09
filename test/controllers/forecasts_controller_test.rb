require "test_helper"

class ForecastsControllerTest < ActionDispatch::IntegrationTest
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
  end

  test "GET / renders the empty search page" do
    get root_path

    assert_response :success
    assert_select "form"
    assert_select "h1", text: /weather/i
  end

  test "submitting an address returns a fresh forecast with a 'Live' badge" do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: GEOCODE_RESPONSE, headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 200, body: WEATHER_RESPONSE, headers: { "Content-Type" => "application/json" })

    get forecast_path, params: { address: "1600 Amphitheatre Pkwy" }

    assert_response :success
    assert_match "94043", response.body
    assert_match "Live", response.body
    refute_match "From cache", response.body
  end

  test "second submission with same ZIP shows a 'From cache' badge" do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: GEOCODE_RESPONSE, headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{api\.open-meteo\.com/v1/forecast})
      .to_return(status: 200, body: WEATHER_RESPONSE, headers: { "Content-Type" => "application/json" })

    get forecast_path, params: { address: "1600 Amphitheatre Pkwy" }
    get forecast_path, params: { address: "1600 Amphitheatre Pkwy" }

    assert_response :success
    assert_match "From cache", response.body
  end

  test "shows an error message when geocoding fails" do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200,
                 body: { "status" => "ZERO_RESULTS", "results" => [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    get forecast_path, params: { address: "asdfghjkl" }

    assert_response :success
    assert_match "couldn't fetch", response.body
  end
end
