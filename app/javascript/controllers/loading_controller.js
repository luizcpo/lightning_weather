import { Controller } from "@hotwired/stimulus"

// Injects a skeleton placeholder into a Turbo Frame while a request is in
// flight, so the user gets immediate feedback on submit. Turbo will replace
// the skeleton with the real response as soon as the fetch resolves.
//
// Usage:
//   <form data-controller="loading"
//         data-loading-frame-value="forecast_result"
//         data-action="submit->loading#showSkeleton">
//     ...
//     <template data-loading-target="template">
//       <!-- skeleton markup -->
//     </template>
//   </form>
export default class extends Controller {
  static values = { frame: String }
  static targets = ["template"]

  showSkeleton() {
    if (!this.hasTemplateTarget) return

    const frame = document.getElementById(this.frameValue)
    if (!frame) return

    frame.innerHTML = this.templateTarget.innerHTML
  }

  // Re-submits the host form (e.g. when the unit toggle changes), but only
  // when the user has already entered an address — avoids firing a search
  // for an empty query the very first time the page loads.
  requestSubmit() {
    const input = this.element.querySelector('[name="address"]')
    if (!input?.value?.trim()) return

    this.element.requestSubmit()
  }
}
