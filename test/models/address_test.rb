require "test_helper"

class AddressTest < ActiveSupport::TestCase
  GOOGLE_RESULT = {
    "formatted_address" => "1600 Amphitheatre Parkway, Mountain View, CA 94043, USA",
    "geometry" => { "location" => { "lat" => 37.4224428, "lng" => -122.0842467 } },
    "address_components" => [
      { "long_name" => "1600",          "short_name" => "1600",         "types" => ["street_number"] },
      { "long_name" => "Mountain View", "short_name" => "Mountain View", "types" => ["locality", "political"] },
      { "long_name" => "California",    "short_name" => "CA",           "types" => ["administrative_area_level_1"] },
      { "long_name" => "United States", "short_name" => "US",           "types" => ["country", "political"] },
      { "long_name" => "94043",         "short_name" => "94043",        "types" => ["postal_code"] }
    ]
  }.freeze

  test ".from_google extracts every supported field" do
    address = Address.from_google(GOOGLE_RESULT)

    assert_equal "1600 Amphitheatre Parkway, Mountain View, CA 94043, USA", address.formatted_address
    assert_equal 37.4224428,      address.latitude
    assert_equal(-122.0842467,    address.longitude)
    assert_equal "94043",         address.zip_code
    assert_equal "Mountain View", address.city
    assert_equal "US",            address.country_code
  end

  test ".from_google accepts symbol-keyed hashes too" do
    address = Address.from_google(GOOGLE_RESULT.deep_symbolize_keys)

    assert_equal "94043", address.zip_code
    assert_equal 37.4224428, address.latitude
  end

  test ".from_google falls back through city type aliases" do
    payload = GOOGLE_RESULT.deep_dup
    payload["address_components"].reject! { |c| c["types"].include?("locality") }
    payload["address_components"] << {
      "long_name" => "Westminster", "short_name" => "Westminster",
      "types" => ["postal_town"]
    }

    address = Address.from_google(payload)
    assert_equal "Westminster", address.city
  end

  test ".from_google returns nil for blank input" do
    assert_nil Address.from_google(nil)
    assert_nil Address.from_google({})
  end

  test "#coordinates? is false when latitude or longitude is missing" do
    refute Address.new(latitude: nil, longitude: -122.0).coordinates?
    refute Address.new(latitude: 37.0, longitude: nil).coordinates?
    assert Address.new(latitude: 37.0, longitude: -122.0).coordinates?
  end
end
