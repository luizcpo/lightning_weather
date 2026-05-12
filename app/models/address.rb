class Address
  include ActiveModel::Model
  include ActiveModel::Attributes

  POSTAL_CODE_TYPE = "postal_code".freeze
  CITY_TYPES = %w[locality postal_town administrative_area_level_2].freeze
  COUNTRY_TYPE = "country".freeze

  attribute :formatted_address, :string
  attribute :latitude, :float
  attribute :longitude, :float
  attribute :zip_code, :string
  attribute :country_code, :string
  attribute :city, :string

  # Builds an Address from a single Google Geocoding API result hash.
  # Keeping the parsing logic on the model means anyone using `Address`
  # can construct one from a Google payload without going through a service.
  def self.from_google(result)
    return nil if result.blank?

    result = result.with_indifferent_access
    location = result.dig(:geometry, :location) || {}
    components = Array(result[:address_components])

    new(
      formatted_address: result[:formatted_address],
      latitude: location[:lat],
      longitude: location[:lng],
      zip_code: extract_component(components, POSTAL_CODE_TYPE),
      country_code: extract_component(components, COUNTRY_TYPE, short: true),
      city: CITY_TYPES.lazy.map { |type| extract_component(components, type) }.find(&:present?)
    )
  end

  def self.extract_component(components, type, short: false)
    component = components.find { |c| Array(c[:types]).include?(type) }
    return nil unless component

    short ? component[:short_name] : component[:long_name]
  end
  private_class_method :extract_component

  def coordinates?
    latitude.present? && longitude.present?
  end
end
