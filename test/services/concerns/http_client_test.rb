require "test_helper"

class HttpClientTest < ActiveSupport::TestCase
  class FakeProvider
    include HttpClient

    provider_name "Fake Provider"

    def initialize(http_client: nil)
      self.http_client = http_client if http_client
    end

    def fetch(url, params = {})
      send(:http_get, url, params)
    end
  end

  test "http_get returns the parsed body as an indifferent hash" do
    stub_request(:get, "https://example.test/")
      .to_return(status: 200,
                 body: { "value" => 42 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    body = FakeProvider.new.fetch("https://example.test/")

    assert_equal 42, body[:value]
    assert_equal 42, body["value"]
  end

  test "http_get raises ProviderError on non-2xx with the provider name" do
    stub_request(:get, "https://example.test/").to_return(status: 503, body: "")

    error = assert_raises(ApplicationService::ProviderError) do
      FakeProvider.new.fetch("https://example.test/")
    end
    assert_match(/Fake Provider/, error.message)
    assert_match(/503/, error.message)
  end

  test "http_get raises NetworkError on Faraday::TimeoutError" do
    stub_request(:get, "https://example.test/").to_timeout

    error = assert_raises(ApplicationService::NetworkError) do
      FakeProvider.new.fetch("https://example.test/")
    end
    assert_match(/Fake Provider/, error.message)
  end

  test "http_get raises ProviderError when the body is not valid JSON" do
    stub_request(:get, "https://example.test/")
      .to_return(status: 200, body: "<<<not json>>>", headers: { "Content-Type" => "text/plain" })

    error = assert_raises(ApplicationService::ProviderError) do
      FakeProvider.new.fetch("https://example.test/")
    end
    assert_match(/Fake Provider/, error.message)
    assert_match(/invalid JSON/i, error.message)
  end

  test "the http_client can be injected via the constructor" do
    injected = Faraday.new do |conn|
      conn.adapter :test do |stub|
        stub.get("/ping") { [200, { "Content-Type" => "application/json" }, '{"pong":true}'] }
      end
    end

    body = FakeProvider.new(http_client: injected).fetch("/ping")
    assert_equal true, body[:pong]
  end
end
