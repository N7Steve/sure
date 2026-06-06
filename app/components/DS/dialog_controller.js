import { Controller } from "@hotwired/stimulus";

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "textarea:not([disabled])",
  "input:not([disabled]):not([type=hidden])",
  "select:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(", ");

// Connects to data-controller="dialog"
export default class extends Controller {
  static targets = ["content"]

  static values = {
    autoOpen: { type: Boolean, default: false },
    reloadOnClose: { type: Boolean, default: false },
    disableClickOutside: { type: Boolean, default: false },
  };

  connect() {
    this._priorFocus = null;
    this._onKeydown = this.#onKeydown.bind(this);
    this._onClose = this.#onClose.bind(this);

    this.element.addEventListener("keydown", this._onKeydown);
    this.element.addEventListener("close", this._onClose);

    if (this.element.open) return;
    if (this.autoOpenValue) {
      this._priorFocus = document.activeElement;
      this.element.showModal();
      this.#focusInitial();
    }

    this.boundTrackMousedown = this.trackMousedown.bind(this);
    document.addEventListener("mousedown", this.boundTrackMousedown);
  }

  disconnect() {
    if (this.boundTrackMousedown) {
      document.removeEventListener("mousedown", this.boundTrackMousedown);
    }
    this.element.removeEventListener("keydown", this._onKeydown);
    this.element.removeEventListener("close", this._onClose);
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
    this.#clearParentModalFrame();

    if (this.reloadOnCloseValue) {
      Turbo.visit(window.location.href);
    }
  }

  // Move focus to the first focusable child unless the dialog already
  // declared one via the autofocus attribute. Native `<dialog>.showModal()`
  // is supposed to do this but the behavior varies across engines.
  #focusInitial() {
    if (this.element.querySelector("[autofocus]")) return;
    this.#focusables()[0]?.focus();
  }

  // Tab/Shift+Tab wrap inside the dialog so focus can't leak to the page
  // behind. Without this an a11y user can tab into the backdrop'd content
  // and lose the modal context entirely.
  #onKeydown(e) {
    if (e.key !== "Tab") return;
    const focusables = this.#focusables();
    if (focusables.length === 0) {
      e.preventDefault();
      return;
    }
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  #onClose() {
    const prior = this._priorFocus;
    this._priorFocus = null;
    if (prior && typeof prior.focus === "function" && document.body.contains(prior)) {
      prior.focus();
    }
  }

  #focusables() {
    return Array.from(this.element.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
      (el) => el.offsetParent !== null || el === document.activeElement,
    );
  }

  // When the dialog lives inside a top-level <turbo-frame id="modal">,
  // emptying the frame on close stops Turbo's page cache from snapshotting
  // an open dialog and reopening it on browser back.
  #clearParentModalFrame() {
    const frame = this.element.closest('turbo-frame[id="modal"]');
    if (frame) frame.innerHTML = "";
  }
}
