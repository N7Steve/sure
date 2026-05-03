import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="scheduled-payment-form"
export default class extends Controller {
  static targets = ["paymentType", "transferFields"]

  connect() {
    this.toggleTransferFields()
  }

  toggleTransferFields() {
    if (!this.hasPaymentTypeTarget || !this.hasTransferFieldsTarget) return

    const isTransfer = this.paymentTypeTarget.value === "transfer"
    this.transferFieldsTarget.classList.toggle("hidden", !isTransfer)
  }
}
