require "faraday"
require "faraday/retry"

class GeocodingService < ApplicationService
  class AddressNotFoundError < NotFoundError; end
  class QuotaExceededError < ProviderError; end
  class RequestDeniedError < ProviderError; end
  class InvalidRequestError < ProviderError; end

  GOOGLE_GEOCODE_URL = "https://maps.googleapis.com/maps/api/geocode/json".freeze

  STATUS_EXCEPTIONS = {
    "ZERO_RESULTS"     => [AddressNotFoundError,  "We couldn't find that address. Please try a different one."],
    "OVER_QUERY_LIMIT" => [QuotaExceededError,    "Google Maps quota exceeded. Try again later."],
    "REQUEST_DENIED"   => [RequestDeniedError,    "Google Maps rejected the request. Verify the API key configuration."],
    "INVALID_REQUEST"  => [InvalidRequestError,   "Google Maps received an invalid request."]
  }.freeze

  attr_reader :query

  def initialize(query)
    @query = query.to_s.strip
  end

  def call
    raise ArgumentError,        "Address cannot be blank."                  if query.blank?
    raise ConfigurationError,   "Google Maps API key is not configured."    if api_key.blank?

    body = request_body
    raise_for_status(body[:status])

    Address.from_google(Array(body[:results]).first)
  rescue Faraday::Error => error
    raise NetworkError, "Network error while contacting Google Maps: #{error.message}"
  rescue JSON::ParserError
    raise ProviderError, "Google Maps returned an invalid JSON response."
  end

  private

  def request_body
    response = http_client.get(GOOGLE_GEOCODE_URL, address: query, key: api_key)
    raise ProviderError, "Geocoding request failed (status #{response.status})." unless response.success?

    body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    body.with_indifferent_access
  end

  def raise_for_status(status)
    return if status == "OK"

    exception_class, message = STATUS_EXCEPTIONS.fetch(status) do
      [ProviderError, "Unexpected response from Google Maps: #{status}."]
    end
    raise exception_class, message
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
