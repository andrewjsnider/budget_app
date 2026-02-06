import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    console.log(this.element)
    this.element.requestSubmit()
  }
}
