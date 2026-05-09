import { Controller } from "@hotwired/stimulus"

// Wires the address input to the modern Google Places API
// (`AutocompleteSuggestion.fetchAutocompleteSuggestions`) and renders a fully
// custom, Tailwind-styled dropdown next to the input.
//
// Why not `google.maps.places.Autocomplete`?
//   The legacy widget has been deprecated since March 2025; new GCP projects
//   no longer get the legacy `.pac-container` UI. The modern API is GA, gives
//   us full UI control, and is what Google recommends going forward.
//
// Required DOM:
//   <form data-controller="places-autocomplete">
//     <input data-places-autocomplete-target="input"
//            data-action="input->places-autocomplete#onInput
//                         keydown->places-autocomplete#onKeydown
//                         focus->places-autocomplete#onFocus">
//     <span data-places-autocomplete-target="spinner" hidden>...</span>
//     <ul   data-places-autocomplete-target="dropdown" hidden role="listbox"></ul>
//   </form>
//
// Reads the API key from <meta name="google-maps-api-key">. If the key is
// missing the controller silently no-ops and the input continues to work as
// a plain text field.
export default class extends Controller {
  static targets = ["input", "spinner", "dropdown", "error"]
  static values = { debounce: { type: Number, default: 250 } }

  static SCRIPT_ID = "google-maps-places-script"

  connect() {
    console.info("[places-autocomplete] connecting…")
    this.suggestions = []
    this.activeIndex = -1
    this.placesReady = false
    this.debounceTimer = null

    this.boundDocumentClick = this.#handleDocumentClick.bind(this)
    document.addEventListener("click", this.boundDocumentClick)

    const apiKey = this.#apiKey()
    if (!apiKey) {
      this.#flashError("Autocomplete disabled — Google Maps API key not configured.")
      return
    }

    this.#loadGoogleMaps(apiKey)
      .then(() => this.#initPlaces())
      .catch((error) => {
        console.error("[places-autocomplete] Failed to load Google Maps JS:", error)
        this.#flashError("Couldn't load Google Maps. Check your network/API key.")
      })
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
  }

  // -- Stimulus actions --------------------------------------------------

  onInput() {
    const query = this.inputTarget.value.trim()

    if (this.debounceTimer) clearTimeout(this.debounceTimer)

    if (query.length < 3) {
      this.#hideSpinner()
      this.#hideDropdown()
      return
    }

    if (!this.placesReady) return

    this.#showSpinner()
    this.debounceTimer = setTimeout(() => this.#fetchSuggestions(query), this.debounceValue)
  }

  onKeydown(event) {
    if (this.dropdownTarget.hasAttribute("hidden")) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.#moveActive(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.#moveActive(-1)
        break
      case "Enter":
        if (this.activeIndex >= 0) {
          event.preventDefault()
          this.#selectSuggestion(this.activeIndex)
        }
        break
      case "Escape":
        event.preventDefault()
        this.#hideDropdown()
        break
    }
  }

  onFocus() {
    if (this.suggestions.length > 0) this.#showDropdown()
  }

  // -- Places API --------------------------------------------------------

  async #initPlaces() {
    try {
      // Prefer the modern dynamic loader when it's available; fall back to
      // the synchronous namespace exposed by the classic script-tag loader.
      let placesLib
      if (typeof window.google?.maps?.importLibrary === "function") {
        placesLib = await window.google.maps.importLibrary("places")
      } else if (window.google?.maps?.places) {
        placesLib = window.google.maps.places
      } else {
        throw new Error("Google Maps Places library is not available")
      }

      this.AutocompleteSuggestion = placesLib.AutocompleteSuggestion
      this.AutocompleteSessionToken = placesLib.AutocompleteSessionToken

      if (!this.AutocompleteSuggestion) {
        this.#flashError(
          "Autocomplete unavailable. Enable 'Places API (New)' for your key in Google Cloud Console."
        )
        return
      }

      this.sessionToken = new this.AutocompleteSessionToken()
      this.placesReady = true
      console.info("[places-autocomplete] ✓ ready (modern AutocompleteSuggestion API)")
    } catch (error) {
      console.error("[places-autocomplete] Could not initialise Places library:", error)
      this.#flashError(`Could not initialise autocomplete: ${error?.message || error}`)
    }
  }

  async #fetchSuggestions(query) {
    try {
      const { suggestions } = await this.AutocompleteSuggestion.fetchAutocompleteSuggestions({
        input: query,
        sessionToken: this.sessionToken
      })

      this.suggestions = suggestions || []
      this.activeIndex = -1
      this.#renderSuggestions()
      this.#clearError()
    } catch (error) {
      console.error("[places-autocomplete] fetchAutocompleteSuggestions failed:", error)
      this.#flashError(this.#friendlyFetchError(error))
      this.suggestions = []
      this.#hideDropdown()
    } finally {
      this.#hideSpinner()
    }
  }

  #friendlyFetchError(error) {
    const message = String(error?.message || error)
    if (/API has not been used|API_NOT_ACTIVATED|disabled/i.test(message)) {
      return "Places API (New) is not enabled for this key. Enable it in Google Cloud Console."
    }
    if (/REQUEST_DENIED|API key|denied/i.test(message)) {
      return "Google rejected the API key. Check restrictions and billing."
    }
    if (/OVER_QUERY_LIMIT|quota/i.test(message)) {
      return "Quota exceeded for this API key."
    }
    return `Autocomplete failed: ${message}`
  }

  async #selectSuggestion(index) {
    const suggestion = this.suggestions[index]
    if (!suggestion?.placePrediction) return

    let label = suggestion.placePrediction.text?.toString?.() || ""

    try {
      const place = suggestion.placePrediction.toPlace()
      await place.fetchFields({ fields: ["formattedAddress"] })
      if (place.formattedAddress) label = place.formattedAddress
    } catch (error) {
      console.warn("[places-autocomplete] Could not fetch place details, falling back to prediction text:", error)
    }

    this.inputTarget.value = label
    this.#hideDropdown()
    this.suggestions = []

    // A session token is meant to bundle one autocomplete session + one
    // place lookup; refresh it after each selection.
    if (this.AutocompleteSessionToken) {
      this.sessionToken = new this.AutocompleteSessionToken()
    }

    this.element.requestSubmit?.()
  }

  // -- Rendering ---------------------------------------------------------

  #renderSuggestions() {
    if (this.suggestions.length === 0) {
      this.#hideDropdown()
      return
    }

    this.dropdownTarget.innerHTML = this.suggestions
      .map((suggestion, index) => this.#suggestionMarkup(suggestion, index))
      .join("")

    this.dropdownTarget.querySelectorAll("[data-suggestion-index]").forEach((el) => {
      el.addEventListener("mousedown", (event) => {
        // mousedown + preventDefault keeps the input focused while clicking.
        event.preventDefault()
        this.#selectSuggestion(parseInt(el.dataset.suggestionIndex, 10))
      })
      el.addEventListener("mouseenter", () => {
        this.activeIndex = parseInt(el.dataset.suggestionIndex, 10)
        this.#updateActiveStyles()
      })
    })

    this.#showDropdown()
  }

  #suggestionMarkup(suggestion, index) {
    const prediction = suggestion.placePrediction
    const main = this.#escape(prediction?.mainText?.text || prediction?.text?.text || "")
    const secondary = this.#escape(prediction?.secondaryText?.text || "")

    return `
      <li role="option"
          data-suggestion-index="${index}"
          class="cursor-pointer px-4 py-3 transition flex items-start gap-3 border-t border-slate-100 first:border-t-0">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="h-5 w-5 mt-0.5 text-indigo-400 flex-shrink-0" aria-hidden="true">
          <path fill-rule="evenodd" d="m9.69 18.933.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.74 5.74 0 0 0 .281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9A7 7 0 1 0 3 9c0 3.492 1.698 5.988 3.355 7.584a13.731 13.731 0 0 0 2.273 1.765 11.842 11.842 0 0 0 .976.544l.062.029.018.008.006.003ZM10 11.25a2.25 2.25 0 1 0 0-4.5 2.25 2.25 0 0 0 0 4.5Z" clip-rule="evenodd" />
        </svg>
        <span class="min-w-0 flex-1">
          <span class="block font-medium text-slate-900 truncate">${main}</span>
          ${secondary ? `<span class="block text-xs text-slate-500 truncate">${secondary}</span>` : ""}
        </span>
      </li>
    `
  }

  #moveActive(delta) {
    if (this.suggestions.length === 0) return

    const total = this.suggestions.length
    if (this.activeIndex === -1) {
      this.activeIndex = delta > 0 ? 0 : total - 1
    } else {
      this.activeIndex = (this.activeIndex + delta + total) % total
    }
    this.#updateActiveStyles()
  }

  #updateActiveStyles() {
    this.dropdownTarget.querySelectorAll("[data-suggestion-index]").forEach((el, i) => {
      const isActive = i === this.activeIndex
      el.classList.toggle("bg-indigo-50", isActive)
      el.classList.toggle("text-indigo-800", isActive)
      if (isActive) el.scrollIntoView({ block: "nearest" })
    })
  }

  // -- Visibility helpers -----------------------------------------------

  #showDropdown() {
    this.dropdownTarget.removeAttribute("hidden")
  }

  #hideDropdown() {
    this.dropdownTarget.setAttribute("hidden", "")
    this.activeIndex = -1
  }

  #showSpinner() {
    if (this.hasSpinnerTarget) this.spinnerTarget.removeAttribute("hidden")
  }

  #hideSpinner() {
    if (this.hasSpinnerTarget) this.spinnerTarget.setAttribute("hidden", "")
  }

  #handleDocumentClick(event) {
    if (!this.element.contains(event.target)) this.#hideDropdown()
  }

  #flashError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.removeAttribute("hidden")
  }

  #clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.setAttribute("hidden", "")
  }

  // -- Loaders ----------------------------------------------------------

  #loadGoogleMaps(apiKey) {
    // Already loaded by either path:
    if (
      typeof window.google?.maps?.importLibrary === "function" ||
      window.google?.maps?.places?.AutocompleteSuggestion
    ) {
      return Promise.resolve()
    }

    const existing = document.getElementById(this.constructor.SCRIPT_ID)
    if (existing) {
      return new Promise((resolve, reject) => {
        existing.addEventListener("load", resolve, { once: true })
        existing.addEventListener("error", reject, { once: true })
      })
    }

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.id = this.constructor.SCRIPT_ID
      script.async = true
      script.defer = true
      // We intentionally omit `loading=async` here — combined with a plain
      // <script src> tag it does not always expose `google.maps.importLibrary`.
      // Without it, all classes under `google.maps.places` are populated by
      // the time `script.onload` fires, which is what `#initPlaces` uses.
      script.src =
        "https://maps.googleapis.com/maps/api/js" +
        `?key=${encodeURIComponent(apiKey)}` +
        "&libraries=places" +
        "&v=weekly"
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }

  #apiKey() {
    return document.querySelector('meta[name="google-maps-api-key"]')?.content?.trim() || null
  }

  #escape(value) {
    return String(value).replace(/[<>&"']/g, (char) => ({
      "<": "&lt;",
      ">": "&gt;",
      "&": "&amp;",
      '"': "&quot;",
      "'": "&#39;"
    })[char])
  }
}
