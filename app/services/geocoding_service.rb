class GeocodingService < ApplicationService
  include HttpClient

  provider_name "Google Maps"

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

  def initialize(query, http_client: nil)
    @query = query.to_s.strip
    self.http_client = http_client if http_client
  end

  def call
    raise ArgumentError,      "Address cannot be blank."                  if query.blank?
    raise ConfigurationError, "Google Maps API key is not configured."    if api_key.blank?

    body = http_get(GOOGLE_GEOCODE_URL, address: query, key: api_key)
    raise_for_status(body[:status])

    Address.from_google(Array(body[:results]).first)
  end

  private

  def raise_for_status(status)
    return if status == "OK"

    exception_class, message = STATUS_EXCEPTIONS.fetch(status) do
      [ProviderError, "Unexpected response from Google Maps: #{status}."]
    end
    raise exception_class, message
  end

  def api_key
    Rails.application.config.x.google_maps_api_key
  end
end
