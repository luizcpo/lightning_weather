require "faraday"
require "faraday/retry"

# Shared HTTP behavior for service objects that talk to external JSON APIs.
#
# What it gives you:
#
#   * A memoized `http_client` (Faraday) with retries, JSON parsing, and
#     sane timeouts — injectable via the constructor or `#http_client=`.
#   * `#http_get(url, params)` that returns the parsed body as an
#     `ActiveSupport::HashWithIndifferentAccess` or raises a typed
#     `ApplicationService::Error` subclass on failure.
#   * A class-level `provider_name "X"` macro that's interpolated into
#     error messages so each service produces human-readable diagnostics.
#
# Example:
#
#   class WeatherService < ApplicationService
#     include HttpClient
#     provider_name "Open-Meteo"
#
#     def call
#       http_get("https://api.example.com/v1", q: "value")
#     end
#   end
module HttpClient
  extend ActiveSupport::Concern

  RETRYABLE_EXCEPTIONS = [Faraday::TimeoutError, Faraday::ConnectionFailed].freeze

  DEFAULT_OPTIONS = {
    timeout: 5,
    open_timeout: 3,
    retries: 2,
    retry_interval: 0.2
  }.freeze

  class_methods do
    # `provider_name "Google Maps"` to set, `provider_name` to read.
    def provider_name(name = nil)
      @provider_name = name.to_s if name
      @provider_name ||= self.name
    end
  end

  attr_writer :http_client

  def http_client
    @http_client ||= build_default_http_client
  end

  private

  def http_get(url, params = {})
    response = http_client.get(url, params)
    unless response.success?
      raise ApplicationService::ProviderError, "#{provider_name} returned status #{response.status}."
    end

    parse_body(response.body)
  rescue Faraday::Error => error
    raise ApplicationService::NetworkError, "Network error while contacting #{provider_name}: #{error.message}"
  rescue JSON::ParserError
    raise ApplicationService::ProviderError, "#{provider_name} returned an invalid JSON response."
  end

  def provider_name
    self.class.provider_name
  end

  def build_default_http_client
    Faraday.new do |conn|
      conn.request :retry, max: DEFAULT_OPTIONS[:retries],
                           interval: DEFAULT_OPTIONS[:retry_interval],
                           exceptions: RETRYABLE_EXCEPTIONS
      conn.response :json, content_type: /\bjson$/
      conn.options.timeout = DEFAULT_OPTIONS[:timeout]
      conn.options.open_timeout = DEFAULT_OPTIONS[:open_timeout]
    end
  end

  def parse_body(body)
    parsed = body.is_a?(Hash) ? body : JSON.parse(body)
    parsed.with_indifferent_access
  end
end
