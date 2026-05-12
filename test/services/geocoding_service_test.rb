require "test_helper"

class GeocodingServiceTest < ActiveSupport::TestCase
  setup do
    Rails.application.config.x.google_maps_api_key = "test-key"
  end

  test "raises ArgumentError when the query is blank" do
    error = assert_raises(ArgumentError) { GeocodingService.call("   ") }
    assert_match(/blank/i, error.message)
  end

  test "raises ConfigurationError when API key is missing" do
    Rails.application.config.x.google_maps_api_key = ""

    error = assert_raises(ApplicationService::ConfigurationError) do
      GeocodingService.call("1600 Amphitheatre Pkwy")
    end
    assert_match(/api key/i, error.message)
  end

  test "returns an Address with the extracted postal code on a successful response" do
    body = {
      "status" => "OK",
      "results" => [
        {
          "formatted_address" => "1600 Amphitheatre Parkway, Mountain View, CA 94043, USA",
          "geometry" => { "location" => { "lat" => 37.4224428, "lng" => -122.0842467 } },
          "address_components" => [
            { "long_name" => "94043",         "short_name" => "94043",         "types" => ["postal_code"] },
            { "long_name" => "Mountain View", "short_name" => "Mountain View", "types" => ["locality", "political"] },
            { "long_name" => "United States", "short_name" => "US",            "types" => ["country", "political"] }
          ]
        }
      ]
    }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    address = GeocodingService.call("1600 Amphitheatre Parkway, Mountain View, CA")

    assert_instance_of Address, address
    assert_equal "94043",         address.zip_code
    assert_equal 37.4224428,      address.latitude
    assert_equal "Mountain View", address.city
    assert_equal "US",            address.country_code
  end

  test "raises AddressNotFoundError on ZERO_RESULTS" do
    body = { "status" => "ZERO_RESULTS", "results" => [] }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    error = assert_raises(GeocodingService::AddressNotFoundError) do
      GeocodingService.call("kjsdhfkjsdhfkjsdhf")
    end
    assert_match(/couldn't find/i, error.message)
  end

  test "raises QuotaExceededError on OVER_QUERY_LIMIT" do
    body = { "status" => "OVER_QUERY_LIMIT", "results" => [] }.to_json

    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json})
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    assert_raises(GeocodingService::QuotaExceededError) { GeocodingService.call("Anywhere") }
  end

  test "raises NetworkError on Faraday::TimeoutError" do
    stub_request(:get, %r{maps\.googleapis\.com/maps/api/geocode/json}).to_timeout

    error = assert_raises(ApplicationService::NetworkError) { GeocodingService.call("Anywhere") }
    assert_match(/network error/i, error.message)
  end
end
