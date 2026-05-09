module ForecastsHelper
  # WMO weather codes used by Open-Meteo. We collapse them into a small set of
  # buckets that map to one emoji + a short description.
  # Reference: https://open-meteo.com/en/docs (Variable "weather_code").
  WEATHER_CODE_MAP = {
    0 => { icon: "☀️", label: "Clear sky" },
    1 => { icon: "🌤️", label: "Mainly clear" },
    2 => { icon: "⛅", label: "Partly cloudy" },
    3 => { icon: "☁️", label: "Overcast" },
    45 => { icon: "🌫️", label: "Fog" },
    48 => { icon: "🌫️", label: "Rime fog" },
    51 => { icon: "🌦️", label: "Light drizzle" },
    53 => { icon: "🌦️", label: "Drizzle" },
    55 => { icon: "🌧️", label: "Heavy drizzle" },
    56 => { icon: "🌧️", label: "Freezing drizzle" },
    57 => { icon: "🌧️", label: "Freezing drizzle" },
    61 => { icon: "🌦️", label: "Light rain" },
    63 => { icon: "🌧️", label: "Rain" },
    65 => { icon: "🌧️", label: "Heavy rain" },
    66 => { icon: "🌧️", label: "Freezing rain" },
    67 => { icon: "🌧️", label: "Freezing rain" },
    71 => { icon: "🌨️", label: "Light snow" },
    73 => { icon: "🌨️", label: "Snow" },
    75 => { icon: "❄️", label: "Heavy snow" },
    77 => { icon: "❄️", label: "Snow grains" },
    80 => { icon: "🌦️", label: "Rain showers" },
    81 => { icon: "🌧️", label: "Rain showers" },
    82 => { icon: "⛈️", label: "Violent showers" },
    85 => { icon: "🌨️", label: "Snow showers" },
    86 => { icon: "❄️", label: "Heavy snow showers" },
    95 => { icon: "⛈️", label: "Thunderstorm" },
    96 => { icon: "⛈️", label: "Thunderstorm w/ hail" },
    99 => { icon: "⛈️", label: "Severe thunderstorm" }
  }.freeze

  DEFAULT_WEATHER = { icon: "🌡️", label: "Conditions" }.freeze

  def weather_icon_for(code)
    WEATHER_CODE_MAP.fetch(code&.to_i, DEFAULT_WEATHER)[:icon]
  end

  def weather_label_for(code)
    WEATHER_CODE_MAP.fetch(code&.to_i, DEFAULT_WEATHER)[:label]
  end

  def format_day(date_string, format: :long)
    return "" if date_string.blank?

    date = Date.parse(date_string)
    case format
    when :short then date.strftime("%a")
    when :date then date.strftime("%b %-d")
    else date.strftime("%A, %B %-d")
    end
  rescue ArgumentError
    ""
  end

  def format_temperature(value, unit)
    return "—" if value.blank?

    "#{value.to_f.round}#{unit}"
  end
end
