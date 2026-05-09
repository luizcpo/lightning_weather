require "faraday"
require "faraday/retry"

class GeocodingService < ApplicationService
  GOOGLE_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json".freeze
  POSTAL_CODE_TYPE = "postal_code".freeze

  attr_reader :address

  def initialize(address)
    @address = address.to_s.strip
  end

  def call
    return Result.failure("Address cannot be blank.") if address.blank?
    return Result.failure("Google Maps API key is not configured.") if api_key.blank?

    response = http_client.get(GOOGLE_GEOCODE_URL, address: address, key: api_key)

    unless response.success?
      return Result.failure("Geocoding request failed (status #{response.status}).")
    end

    body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    status = body["status"]

    case status
    when "OK"
      Result.success(parse_first_result(body["results"].first))
    when "ZERO_RESULTS"
      Result.failure("We couldn't find that address. Please try a different one.")
    when "OVER_QUERY_LIMIT", "REQUEST_DENIED", "INVALID_REQUEST"
      Result.failure("Google Maps API returned an error: #{status}.")
    else
      Result.failure("Unexpected response from Google Maps: #{status}.")
    end
  rescue Faraday::Error => e
    Result.failure("Network error while contacting Google Maps: #{e.message}.")
  rescue JSON::ParserError
    Result.failure("Invalid response from Google Maps.")
  end

  private

  def parse_first_result(result)
    location = result.dig("geometry", "location") || {}
    components = result["address_components"] || []

    {
      formatted_address: result["formatted_address"],
      latitude: location["lat"]&.to_f,
      longitude: location["lng"]&.to_f,
      zip_code: extract_component(components, POSTAL_CODE_TYPE),
      country_code: extract_component(components, "country", short: true),
      city: extract_component(components, "locality") ||
            extract_component(components, "postal_town") ||
            extract_component(components, "administrative_area_level_2")
    }
  end

  def extract_component(components, type, short: false)
    component = components.find { |c| c["types"]&.include?(type) }
    return nil unless component

    short ? component["short_name"] : component["long_name"]
  end

  def http_client
    @http_client ||= Faraday.new do |conn|
      conn.request :retry, max: 2, interval: 0.2,
                           exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
      conn.response :json, content_type: /\bjson$/
      conn.options.timeout = 5
      conn.options.open_timeout = 3
    end
  end

  def api_key
    Rails.application.config.x.google_maps_api_key
  end
end
