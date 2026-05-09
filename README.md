# ⚡ Lightning Weather

A small, beautiful Ruby on Rails 8 application that turns any address into a current
weather report and a 7-day outlook. Search results are cached for **30 minutes per
ZIP code** and the UI clearly shows when a result was served from cache.

![flow](https://img.shields.io/badge/Rails-8.0-cc0000?logo=rubyonrails) ![hotwire](https://img.shields.io/badge/Hotwire-Turbo%20%2B%20Stimulus-3a9bdc) ![tailwind](https://img.shields.io/badge/Tailwind-4-06b6d4?logo=tailwindcss) ![tests](https://img.shields.io/badge/tests-16%20passing-22c55e)

---

## ✨ Features

- 🔎 **Google Places autocomplete** for friendly address input.
- 🗺️ **Server-side geocoding** via the Google Maps Geocoding API to extract the canonical ZIP code.
- 🌡️ **Current temperature, "feels like", humidity, wind** plus today's high/low.
- 📅 **7-day outlook** with daily highs, lows and precipitation probability.
- ⚡ **30-minute Rails cache keyed by ZIP code** — different addresses inside the same ZIP share a cached payload.
- 🏷️ **Cache indicator** ("Live" / "From cache") rendered on every result.
- 🎚️ **Imperial / metric toggle** (°F · mph ⇄ °C · km/h), each with its own cache namespace.
- 🚀 **Hotwire-powered partial updates** via Turbo Frames — no full-page reloads on search.

---

## 🛠️ Tech stack

| Concern              | Choice                                                                 |
|----------------------|------------------------------------------------------------------------|
| Framework            | Ruby on Rails **8.0** (latest 8.0.x, Ruby 3.3-compatible)              |
| Front-end            | Hotwire (**Turbo + Stimulus**) + **Tailwind CSS v4**                   |
| Address autocomplete | **Google Places API** (loaded lazily by a Stimulus controller)         |
| Geocoding            | **Google Maps Geocoding API** (server-side, called from Rails)         |
| Weather provider     | **Open-Meteo** — free, key-less, generous rate limits                  |
| HTTP client          | **Faraday** (+ `faraday-retry`)                                        |
| Cache                | `Rails.cache` (`:memory_store` in dev/test, your choice in prod)       |
| Tests                | Minitest + **WebMock** for HTTP stubbing                               |

---

## 🚀 Getting started

### 1. Prerequisites

- **Ruby 3.3+** (the project pins Ruby 3.3.0 via `.ruby-version`)
- **Bundler** (`gem install bundler`)
- A **Google Maps API key** with these APIs enabled:
  - *Maps JavaScript API* (front-end autocomplete)
  - *Places API* (front-end autocomplete)
  - *Geocoding API* (server-side address → ZIP lookup)

> The weather provider (Open-Meteo) does **not** require an API key.

### 2. Install dependencies

```bash
bundle install
```

### 3. Configure your Google Maps API key

Copy the example file and fill in your key:

```bash
cp .env.example .env
# then edit .env:
# GOOGLE_MAPS_API_KEY=AIza...your-key...
```

`dotenv-rails` will load that file in development & test. For production you can
either set the same `GOOGLE_MAPS_API_KEY` environment variable or store the key
inside Rails' encrypted credentials:

```bash
EDITOR="code --wait" bin/rails credentials:edit
# google_maps:
#   api_key: AIza...your-key...
```

### 4. Run the database setup (just creates the empty SQLite file)

```bash
bin/rails db:prepare
```

### 5. Start the development server

```bash
bin/dev
```

This launches both the Rails server and the Tailwind CSS watcher via `Procfile.dev`.
Open <http://localhost:3000> and start typing an address.

### 6. Run the tests

```bash
bin/rails test
```

---

## 🧠 Approach

The problem boils down to three concerns:

1. **Resolve a free-form address into something cacheable** (a ZIP code).
2. **Fetch a forecast for that location** from a reliable provider.
3. **Cache the forecast for 30 minutes** and surface that cache state in the UI.

The application is organised around those three steps:

```
ForecastFetcher (orchestrator)
  ├── GeocodingService  → Google Maps Geocoding API   (address → lat/lng + ZIP)
  └── WeatherService    → Open-Meteo /v1/forecast     (lat/lng → forecast JSON)
```

`ForecastFetcher` is the only service the controller talks to. It:

1. Calls `GeocodingService` to turn the address into a `{ formatted_address, lat, lng, zip_code, … }` hash.
2. Builds the cache key as `forecasts:<unit_system>:<zip_code>`.
3. Uses `Rails.cache.exist?` *before* `Rails.cache.fetch` to record whether the
   payload was already cached — this is what powers the "From cache" badge.
4. On a cache miss, calls `WeatherService` and stores the merged payload for
   `30.minutes`.
5. Wraps the result in a `Forecast` PORO (an `ActiveModel::Model`) that exposes
   view-friendly methods like `temperature_unit`, `today`, `from_cache?`.

### Why these libraries / decisions?

| Decision | Rationale |
|---|---|
| **Rails 8 + Hotwire + Tailwind CSS** | The user asked for the latest Rails with Hotwire. Tailwind v4 was generated via the official `--css tailwind` flag and gives us a beautiful, utility-driven UI without writing custom CSS. |
| **Open-Meteo** as weather provider | Free, no API key, well-documented, returns current + daily forecasts in a single call, supports both unit systems via query params. Removes a configuration step compared to OpenWeatherMap. |
| **Google Maps for both autocomplete & geocoding** | The user explicitly asked for Google Maps. Keeping both client-side (Places autocomplete) and server-side (Geocoding API) reuses a single key and ensures the ZIP we cache by always comes from a canonical source — even if the user just types and hits Enter without picking a suggestion. |
| **Cache by ZIP, not address** | The requirement is "Cache the forecast details for 30 minutes for all subsequent requests by zip codes." Two different addresses on the same street share a ZIP and therefore the same forecast — caching by ZIP keeps that DRY and matches the spec. |
| **`memory_store` cache** | The user asked for a "simple Rails cache". `:memory_store` is the simplest correct choice for a single-process dev/test setup. Swapping in `:solid_cache_store`, `:redis_cache_store` or `:file_store` for production is a one-line config change. |
| **`Rails.cache.exist?` + `Rails.cache.fetch`** | Lets us know whether the upcoming `fetch` will be a hit or a miss — the only reliable way to power the "From cache" badge with Rails' standard cache API. |
| **Service objects with a tiny `Result` struct** | Keeps controllers thin and gives every external integration a uniform `success?` / `failure?` interface. No giant exception ladder, no special exception classes leaking into views. |
| **`Forecast` as an `ActiveModel` PORO** | We don't need persistence, but we want view helpers and a stable presentation API. `ActiveModel::Attributes` gives us coercion + safe `nil` handling for free. |
| **Faraday + retries** | Single HTTP abstraction with idiomatic JSON parsing, configurable timeouts, and built-in retry on transient network errors. |
| **Stimulus controller for Places autocomplete** | Lazy-loads the Google Maps JS only when the input is on the page, reads the API key from a `<meta>` tag injected by the layout, and degrades gracefully (the form still works as a plain text field) if the key isn't configured. |
| **Turbo Frames** | The result block lives inside `<turbo-frame id="forecast_result">`. Submissions update only that frame and push a new history entry, so the search input stays focused and the URL stays shareable. |

---

## 📁 Project layout

```
app/
├── controllers/
│   └── forecasts_controller.rb       # Single show action, returns html or turbo_stream
├── services/
│   ├── application_service.rb        # Tiny base class with .call + Result struct
│   ├── geocoding_service.rb          # Google Maps Geocoding wrapper
│   ├── weather_service.rb            # Open-Meteo wrapper
│   └── forecast_fetcher.rb           # Orchestrator + cache layer
├── models/
│   └── forecast.rb                   # ActiveModel PORO used by the views
├── helpers/
│   └── forecasts_helper.rb           # WMO weather code → emoji/label, formatters
├── views/forecasts/
│   ├── show.html.erb
│   ├── show.turbo_stream.erb
│   ├── _search_form.html.erb
│   ├── _forecast.html.erb
│   ├── _empty_state.html.erb
│   └── _error.html.erb
└── javascript/controllers/
    └── places_autocomplete_controller.js   # Lazy-loads Google Places JS
config/
├── initializers/google_maps.rb       # Resolves ENV / credentials → config.x
└── routes.rb                         # `resource :forecast, only: :show` + root
test/
├── controllers/forecasts_controller_test.rb
└── services/
    ├── forecast_fetcher_test.rb
    ├── geocoding_service_test.rb
    └── weather_service_test.rb
```

---

## 🧪 Testing notes

- All HTTP calls are stubbed with **WebMock** — the suite never hits the
  network.
- `Rails.cache` is cleared before each test (see `test/test_helper.rb`).
- The `ForecastFetcher` test suite verifies all three caching invariants:
  - First call hits the network and is **not** marked as cached.
  - Second call within 30 minutes is served from cache and **is** marked.
  - A different address sharing the same ZIP also hits the cache (keyed by ZIP).
- The controller tests assert that the `Live` and `From cache` badges show up
  on the rendered page in the right scenarios.

Run only the cache-related suite:

```bash
bin/rails test test/services/forecast_fetcher_test.rb
```

---

## 🔧 Configuration knobs

| Setting | Where | Default |
|---|---|---|
| Cache TTL | `ForecastFetcher::CACHE_TTL` | `30.minutes` |
| Cache namespace | `ForecastFetcher::CACHE_NAMESPACE` | `"forecasts"` |
| Default unit system | `ForecastsController#show` | `"imperial"` |
| Forecast horizon | `WeatherService#query_params[:forecast_days]` | `7` |
| HTTP timeouts | `*_service.rb` `http_client` | 5s read / 3s connect |

---

## 🌱 Possible next steps

These are intentionally out of scope for this exercise but would be the natural
follow-ups:

- Persist a small history of recent searches (per session) for one-click recall.
- Geolocate the user via the browser as a default value for the input.
- Replace `:memory_store` with `:solid_cache_store` in production so caches
  survive process restarts.
- Add system tests with Capybara to drive the autocomplete flow end-to-end.
- Track cache hit ratio and external-API latency via `ActiveSupport::Notifications`.
