import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]

  connect() {
    this.inputTarget.addEventListener("input", () => this.#showSubmit())
    this.inputTarget.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        this.element.requestSubmit()
      }
    })
  }

  #showSubmit() {
    this.submitTarget.classList.remove("hidden")
  }
}
