import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="scheduled-payment-form"
export default class extends Controller {
  static targets = [
    "paymentType",
    "transferFields",
    "frequency",
    "endDateFields",
    "amountEstimated",
    "autoConfirmFields",
  ];

  connect() {
    this.toggleTransferFields();
    this.toggleFrequencyFields();
    this.toggleEstimatedAmountFields();
  }

  toggleTransferFields() {
    if (!this.hasPaymentTypeTarget || !this.hasTransferFieldsTarget) return;

    const isTransfer = this.paymentTypeTarget.value === "transfer";
    this.transferFieldsTarget.classList.toggle("hidden", !isTransfer);
  }

  toggleFrequencyFields() {
    if (!this.hasFrequencyTarget || !this.hasEndDateFieldsTarget) return;

    const isOnce = this.frequencyTarget.value === "once";
    this.endDateFieldsTarget.classList.toggle("hidden", isOnce);
    this.endDateFieldsTarget.querySelectorAll("input").forEach((input) => {
      input.disabled = isOnce;
    });
  }

  toggleEstimatedAmountFields() {
    if (!this.hasAmountEstimatedTarget || !this.hasAutoConfirmFieldsTarget)
      return;

    const isEstimated = this.amountEstimatedTarget.checked;
    this.autoConfirmFieldsTarget.classList.toggle("hidden", isEstimated);
    const autoConfirmToggle = this.autoConfirmFieldsTarget.querySelector(
      "input[type=checkbox]",
    );
    if (isEstimated && autoConfirmToggle) autoConfirmToggle.checked = false;
  }
}
