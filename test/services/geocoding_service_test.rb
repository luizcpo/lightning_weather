require "test_helper"

class GeocodingServiceTest < ActiveSupport::TestCase
  setup do
    Rails.application.config.x.google_maps_api_key = "test-key"
  end

  test "returns failure when address is blank" do
    result = GeocodingService.call("   ")

    assert_predicate result, :failure?
    assert_match(/blank/i, result.error)
  end

  test "returns failure when API key is missing" do
    Rails.application.config.x.google_maps_api_key = ""

    result = GeocodingService.call("1600 Amphitheatre Pkwy")

    assert_predicate result, :failure?
    assert_match(/api key/i, result.error)
  end

  test "parses a successful response and extracts the postal code" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "1600 Amphitheatre Parkway, Mountain View, CA 94043, USA",
          "geometry" => { "location" => { "lat" => 37.4224428, "lng" => -122.0842467 } },
          "address_components" => [
            { "long_name" => "94043", "short_name" => "94043", "types" => ["postal_code"] },
            { "long_name" => "Mountain View", "short_name" => "Mountain View", "types" => ["locality", "political"] },
            { "long_name" => "United States", "short_name" => "US", "types" => ["country", "political"] }
          ]
        }
      ]
    }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = GeocodingService.call("1600 Amphitheatre Parkway, Mountain View, CA")

    assert_predicate result, :success?
    assert_equal "94043", result.value[:zip_code]
    assert_equal 37.4224428, result.value[:latitude]
    assert_equal "Mountain View", result.value[:city]
    assert_equal "US", result.value[:country_code]
  end

  test "returns friendly failure for ZERO_RESULTS" do
    body = { "status" => "ZERO_RESULTS", "results" => [] }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = GeocodingService.call("kjsdhfkjsdhfkjsdhf")

    assert_predicate result, :failure?
    assert_match(/couldn't find/i, result.error)
  end

  test "wraps Faraday network errors" do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json}).to_timeout

    result = GeocodingService.call("Anywhere")

    assert_predicate result, :failure?
    assert_match(/network error/i, result.error)
  end
end
