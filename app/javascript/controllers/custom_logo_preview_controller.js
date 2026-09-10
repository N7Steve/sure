import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "clearButton",
    "customImage",
    "deleteField",
    "fallbackImage",
    "input",
    "placeholder",
    "previewImage",
    "uploadText",
  ];

  preview(event) {
    const file = event.target.files[0];
    if (!file) return;

    this.releasePreviewUrl();
    this.previewUrl = URL.createObjectURL(file);
    this.previewImageTarget.src = this.previewUrl;
    this.hide(this.customImageTarget);
    this.hide(this.fallbackImageTarget);
    this.hide(this.placeholderTarget);
    this.show(this.previewImageTarget);
    this.show(this.clearButtonTarget);
    this.deleteFieldTarget.value = "0";
    this.uploadTextTarget.textContent =
      this.uploadTextTarget.dataset.changeText;
  }

  clear() {
    this.inputTarget.value = "";
    this.releasePreviewUrl();
    this.hide(this.customImageTarget);
    this.hide(this.previewImageTarget);

    if (this.fallbackImageTarget.getAttribute("src")) {
      this.show(this.fallbackImageTarget);
      this.hide(this.placeholderTarget);
    } else {
      this.hide(this.fallbackImageTarget);
      this.show(this.placeholderTarget);
    }

    this.hide(this.clearButtonTarget);
    this.deleteFieldTarget.value = "1";
    this.uploadTextTarget.textContent =
      this.uploadTextTarget.dataset.uploadText;
  }

  disconnect() {
    this.releasePreviewUrl();
  }

  hide(element) {
    element.classList.add("hidden");
  }

  show(element) {
    element.classList.remove("hidden");
  }

  releasePreviewUrl() {
    if (!this.previewUrl) return;

    URL.revokeObjectURL(this.previewUrl);
    this.previewUrl = null;
  }
}
