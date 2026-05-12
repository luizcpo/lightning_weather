class ApplicationService
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ProviderError < Error; end
  class NetworkError < Error; end
  class NotFoundError < Error; end

  def self.call(...)
    new(...).call
  end
end
