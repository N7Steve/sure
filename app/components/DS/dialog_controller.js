import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="dialog"
export default class extends Controller {
  static targets = ["content"]

  static values = {
    autoOpen: { type: Boolean, default: false },
    reloadOnClose: { type: Boolean, default: false },
    disableClickOutside: { type: Boolean, default: false },
  };

  connect() {
    if (this.element.open) return;
    if (this.autoOpenValue) {
      this.element.showModal();
    }

    this.boundTrackMousedown = this.trackMousedown.bind(this);
    document.addEventListener("mousedown", this.boundTrackMousedown);
  }

  disconnect() {
    if (this.boundTrackMousedown) {
      document.removeEventListener("mousedown", this.boundTrackMousedown);
    }
  }

  trackMousedown(e) {
    this.mousedownTarget = e.target;
  }

  // If the user clicks anywhere outside of the visible content, close the dialog
  clickOutside(e) {
    if (this.disableClickOutsideValue) return;

    // Ignore if mousedown started inside the content (e.g., text selection drag out)
    if (this.mousedownTarget && this.contentTarget.contains(this.mousedownTarget)) return;

    // Only close if the click lands directly on the modal backdrop or its structural wrapper
    // By checking if the clicked target contains the contentTarget, we ensure we're clicking
    // the outer container, not a portal/dropdown item appended to the body
    if (e.target === this.element || e.target.contains(this.contentTarget)) {
      this.close();
    }
  }

  close() {
    this.element.close();

    if (this.reloadOnCloseValue) {
      Turbo.visit(window.location.href);
    }
  }
}
