module ForecastsHelper
  # Maps every WMO weather code Open-Meteo can return to a Lucide icon name.
  # The icons themselves live in `app/assets/svg/icons/lucide/outline/` and
  # are rendered via the `icon` helper from the `rails_icons` gem.
  # Reference: https://open-meteo.com/en/docs (Variable "weather_code").
  WEATHER_ICONS = {
    0  => "sun",
    1  => "sun",
    2  => "cloud-sun",
    3  => "cloud",
    45 => "cloud-fog",
    48 => "cloud-fog",
    51 => "cloud-drizzle",
    53 => "cloud-drizzle",
    55 => "cloud-drizzle",
    56 => "cloud-drizzle",
    57 => "cloud-drizzle",
    61 => "cloud-rain",
    63 => "cloud-rain",
    65 => "cloud-rain",
    66 => "cloud-rain",
    67 => "cloud-rain",
    71 => "cloud-snow",
    73 => "cloud-snow",
    75 => "cloud-snow",
    77 => "cloud-snow",
    80 => "cloud-rain",
    81 => "cloud-rain",
    82 => "cloud-rain",
    85 => "cloud-snow",
    86 => "cloud-snow",
    95 => "cloud-lightning",
    96 => "cloud-lightning",
    99 => "cloud-lightning"
  }.freeze

  WEATHER_LABELS = {
    0  => "Clear sky",
    1  => "Mainly clear",
    2  => "Partly cloudy",
    3  => "Overcast",
    45 => "Fog",
    48 => "Rime fog",
    51 => "Light drizzle",
    53 => "Drizzle",
    55 => "Heavy drizzle",
    56 => "Freezing drizzle",
    57 => "Freezing drizzle",
    61 => "Light rain",
    63 => "Rain",
    65 => "Heavy rain",
    66 => "Freezing rain",
    67 => "Freezing rain",
    71 => "Light snow",
    73 => "Snow",
    75 => "Heavy snow",
    77 => "Snow grains",
    80 => "Rain showers",
    81 => "Rain showers",
    82 => "Violent showers",
    85 => "Snow showers",
    86 => "Heavy snow showers",
    95 => "Thunderstorm",
    96 => "Thunderstorm with hail",
    99 => "Severe thunderstorm"
  }.freeze

  DEFAULT_ICON = "sun".freeze
  DEFAULT_LABEL = "Conditions".freeze

  def weather_icon(code, **options)
    name = WEATHER_ICONS.fetch(code&.to_i, DEFAULT_ICON)
    options[:class] ||= "h-10 w-10"
    icon(name, **options)
  end

  def weather_label(code)
    WEATHER_LABELS.fetch(code&.to_i, DEFAULT_LABEL)
  end

  def format_day(date_string, format: :long)
    return "" if date_string.blank?

    date = Date.parse(date_string)
    case format
    when :short then date.strftime("%a")
    when :date  then date.strftime("%b %-d")
    else             date.strftime("%A, %B %-d")
    end
  rescue ArgumentError
    ""
  end

  def format_temperature(value, unit)
    return "—" if value.blank?

    "#{value.to_f.round}#{unit}"
  end
end
