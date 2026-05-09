# Centralised access to the Google Maps API key.
#
# Resolution order:
#   1. ENV["GOOGLE_MAPS_API_KEY"]            (preferred for development & CI)
#   2. Rails.application.credentials.google_maps&.api_key (preferred for production)
#
# The key is exposed both server-side (for the Geocoding API used by
# GeocodingService) and client-side (rendered into a <meta> tag in the layout
# and consumed by the places_autocomplete Stimulus controller).
api_key = ENV["GOOGLE_MAPS_API_KEY"].presence ||
          Rails.application.credentials.dig(:google_maps, :api_key)

Rails.application.config.x.google_maps_api_key = api_key.to_s
