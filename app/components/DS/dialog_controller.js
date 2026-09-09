import { Controller } from "@hotwired/stimulus";

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "textarea:not([disabled])",
  "input:not([disabled]):not([type=hidden])",
  "select:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(", ");
const OPEN_DURATION = 180;
const CLOSE_DURATION = 120;
const EASING = "ease-out";

// Connects to data-controller="dialog"
export default class extends Controller {
  static targets = ["content", "backdrop"];

  static values = {
    autoOpen: { type: Boolean, default: false },
    reloadOnClose: { type: Boolean, default: false },
    disableClickOutside: { type: Boolean, default: false },
  };

  connect() {
    this._connected = true;
    this._closing = false;
    this._submittingAfterClose = false;
    this._pendingSubmit = false;
    this._priorFocus = null;
    this._onKeydown = this.#onKeydown.bind(this);
    this._onClose = this.#onClose.bind(this);
    this._onCancel = this.#onCancel.bind(this);
    this._onSubmit = this.#onSubmit.bind(this);

    this._openObserver = new MutationObserver(() => {
      if (this.element.open && !this._closing) this.#animateOpen();
    });
    this._openObserver.observe(this.element, {
      attributes: true,
      attributeFilter: ["open"],
    });

    this.element.addEventListener("keydown", this._onKeydown);
    this.element.addEventListener("close", this._onClose);
    this.element.addEventListener("cancel", this._onCancel);
    this.element.addEventListener("submit", this._onSubmit);

    if (this.element.open) this.#animateOpen();
    if (!this.element.open && this.autoOpenValue) this.open();

    this.boundTrackMousedown = this.trackMousedown.bind(this);
    document.addEventListener("mousedown", this.boundTrackMousedown);
  }

  disconnect() {
    this._connected = false;
    this._closing = false;
    this._openObserver?.disconnect();
    this.#cancelAnimations();
    if (this.boundTrackMousedown) {
      document.removeEventListener("mousedown", this.boundTrackMousedown);
    }
    this.element.removeEventListener("keydown", this._onKeydown);
    this.element.removeEventListener("close", this._onClose);
    this.element.removeEventListener("cancel", this._onCancel);
    this.element.removeEventListener("submit", this._onSubmit);
  }

  trackMousedown(event) {
    this.mousedownTarget = event.target;
  }

  // If the user clicks anywhere outside of the visible content, close the dialog
  clickOutside(event) {
    if (this.disableClickOutsideValue) return;

    // Ignore if mousedown started inside the content (e.g., text selection drag out)
    if (
      this.mousedownTarget &&
      this.contentTarget.contains(this.mousedownTarget)
    )
      return;

    // Only close if the click lands directly on the modal backdrop or its structural wrapper
    // By checking if the clicked target contains the contentTarget, we ensure we're clicking
    // the outer container, not a portal/dropdown item appended to the body
    if (
      event.target === this.element ||
      event.target === this.backdropTarget ||
      event.target.contains(this.contentTarget)
    ) {
      this.close();
    }
  }

  open() {
    if (this.element.open) return;

    this._priorFocus = document.activeElement;
    this.element.showModal();
    this.#focusInitial();
  }

  close() {
    return this.#close();
  }

  closeBeforeSubmit(event) {
    if (this._submittingAfterClose) return;

    event.preventDefault();
    if (this._pendingSubmit) return;

    this._pendingSubmit = true;
    const form = event.target;
    const submitter = event.submitter;

    this.#close({ clearFrame: false, reload: false }).then((closed) => {
      this._pendingSubmit = false;
      if (!closed || !form.isConnected) return;

      this._submittingAfterClose = true;
      try {
        if (submitter) {
          form.requestSubmit(submitter);
        } else {
          form.requestSubmit();
        }
      } finally {
        this._submittingAfterClose = false;
      }
    });
  }

  #close({ clearFrame = true, reload = true } = {}) {
    if (!this.element.open || this._closing) return Promise.resolve(false);

    if (this.#prefersReducedMotion()) {
      this.#finishClose({ clearFrame, reload });
      return Promise.resolve(true);
    }

    this._closing = true;
    this.#cancelAnimations();
    this._contentAnimation = this.contentTarget.animate(
      { opacity: [1, 0] },
      { duration: CLOSE_DURATION, easing: EASING },
    );
    this._backdropAnimation = this.backdropTarget.animate(
      { opacity: [1, 0] },
      { duration: CLOSE_DURATION, easing: EASING },
    );

    return Promise.allSettled([
      this._contentAnimation.finished,
      this._backdropAnimation.finished,
    ]).then(() => {
      if (!this._connected || !this._closing) return false;

      this.#finishClose({ clearFrame, reload });
      return true;
    });
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
  #onKeydown(event) {
    if (event.key !== "Tab") return;
    const focusables = this.#focusables();
    if (focusables.length === 0) {
      event.preventDefault();
      return;
    }
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  #onClose() {
    const prior = this._priorFocus;
    this._priorFocus = null;
    if (
      prior &&
      typeof prior.focus === "function" &&
      document.body.contains(prior)
    ) {
      prior.focus();
    }
  }

  #onCancel(event) {
    event.preventDefault();
    this.close();
  }

  #onSubmit(event) {
    if (event.target.method !== "dialog") return;

    event.preventDefault();
    this.element.returnValue = event.submitter?.value || "";
    this.close();
  }

  #animateOpen() {
    if (this.#prefersReducedMotion()) return;

    this.#cancelAnimations();
    this._contentAnimation = this.contentTarget.animate(
      { opacity: [0, 1] },
      { duration: OPEN_DURATION, easing: EASING },
    );
    this._backdropAnimation = this.backdropTarget.animate(
      { opacity: [0, 1] },
      { duration: OPEN_DURATION, easing: EASING },
    );
  }

  #finishClose({ clearFrame = true, reload = true } = {}) {
    this._closing = false;
    this.#cancelAnimations();
    this.element.close();
    if (clearFrame) this.#clearParentModalFrame();

    if (reload && this.reloadOnCloseValue) {
      Turbo.visit(window.location.href);
    }
  }

  #cancelAnimations() {
    this._contentAnimation?.cancel();
    this._backdropAnimation?.cancel();
    this._contentAnimation = null;
    this._backdropAnimation = null;
  }

  #prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }

  #focusables() {
    return Array.from(this.element.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
      (element) =>
        element.offsetParent !== null || element === document.activeElement,
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
