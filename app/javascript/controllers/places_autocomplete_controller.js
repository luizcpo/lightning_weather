import { Controller } from "@hotwired/stimulus"

// Wires Google Places Autocomplete onto a plain text input and shows a
// debounced spinner while the user is actively typing so they get visual
// feedback that suggestions are being fetched.
//
// Usage:
//   <form data-controller="places-autocomplete">
//     <input data-places-autocomplete-target="input">
//     <span  data-places-autocomplete-target="spinner" hidden>...</span>
//   </form>
//
// The Google Maps JS API is loaded lazily on the first connect, so the rest of
// the page is not penalised when the user never focuses the input. The API key
// is read from <meta name="google-maps-api-key">; if it is missing the
// controller silently no-ops and the user can still type a free-form address.
export default class extends Controller {
  static targets = ["input", "spinner"]
  static values = { debounce: { type: Number, default: 350 } }

  static SCRIPT_ID = "google-maps-places-script"

  connect() {
    this.boundHandleInput = this.#handleInput.bind(this)
    this.boundBlur = () => this.#hideSpinner()
    this.inputTarget.addEventListener("input", this.boundHandleInput)
    this.inputTarget.addEventListener("blur", this.boundBlur, { passive: true })

    const apiKey = this.#apiKey()
    if (!apiKey) {
      console.warn(
        "[places-autocomplete] No Google Maps API key in <meta name=\"google-maps-api-key\">. " +
          "Autocomplete disabled — the input still works as a regular text field."
      )
      return
    }

    this.#loadGoogleMaps(apiKey)
      .then(() => this.#initAutocomplete())
      .catch((error) => {
        console.error("[places-autocomplete] Failed to load Google Maps JS:", error)
      })
  }

  disconnect() {
    this.inputTarget.removeEventListener("input", this.boundHandleInput)
    this.inputTarget.removeEventListener("blur", this.boundBlur)
    if (this.placeChangedListener && window.google) {
      window.google.maps.event.removeListener(this.placeChangedListener)
    }
    if (this.spinnerTimeout) clearTimeout(this.spinnerTimeout)
  }

  #handleInput() {
    const value = this.inputTarget.value.trim()

    if (value.length < 2) {
      this.#hideSpinner()
      return
    }

    this.#showSpinner()
    if (this.spinnerTimeout) clearTimeout(this.spinnerTimeout)
    this.spinnerTimeout = setTimeout(() => this.#hideSpinner(), this.debounceValue + 300)
  }

  #showSpinner() {
    if (!this.hasSpinnerTarget) return
    this.spinnerTarget.removeAttribute("hidden")
  }

  #hideSpinner() {
    if (!this.hasSpinnerTarget) return
    this.spinnerTarget.setAttribute("hidden", "")
  }

  #initAutocomplete() {
    if (!this.hasInputTarget) return

    if (!window.google?.maps?.places?.Autocomplete) {
      console.error(
        "[places-autocomplete] google.maps.places.Autocomplete not available. " +
          "Check that the Places API and Maps JavaScript API are enabled for your key."
      )
      return
    }

    this.autocomplete = new window.google.maps.places.Autocomplete(this.inputTarget, {
      fields: ["formatted_address", "address_components", "geometry"],
      types: ["geocode"]
    })

    this.placeChangedListener = this.autocomplete.addListener("place_changed", () => {
      this.#hideSpinner()
      const place = this.autocomplete.getPlace()
      if (place?.formatted_address) {
        this.inputTarget.value = place.formatted_address
        this.element.requestSubmit?.()
      }
    })

    // Prevent Enter from prematurely submitting the form while a suggestion
    // is highlighted in the dropdown.
    this.inputTarget.addEventListener("keydown", (event) => {
      const dropdownVisible = document.querySelector(".pac-container:not([style*='display: none'])")
      if (event.key === "Enter" && dropdownVisible) event.preventDefault()
    })
  }

  #loadGoogleMaps(apiKey) {
    if (window.google?.maps?.places) return Promise.resolve()

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
      script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}&libraries=places&loading=async`
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }

  #apiKey() {
    const meta = document.querySelector('meta[name="google-maps-api-key"]')
    return meta?.content?.trim() || null
  }
}
