import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.classList.add("flash-updated")
    window.setTimeout(() => {
      this.element.classList.remove("flash-updated")
    }, 1300)
  }
}