import { Controller } from "@hotwired/stimulus";

// Remembers whether a <details> section is open, per device, so a panel the
// user has collapsed stays collapsed instead of reappearing on every render.
// Same storage approach as privacy mode and the sidebar width.
//
// The element keeps its server-rendered `open` state until connect() runs, so
// a collapsed section flashes open for a frame on a cold load. Reading storage
// in connect() rather than waiting for a turbo event keeps that to one frame.
export default class extends Controller {
  static values = { key: String };

  connect() {
    const stored = this.storedState;
    if (stored !== null) {
      this.element.open = stored === "true";
    } else {
      this.persistState();
    }

    this.toggleHandler = () => this.persistState();
    this.element.addEventListener("toggle", this.toggleHandler);
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.toggleHandler);
  }

  // Same-URL Turbo refreshes use morphing. Preserve the client-owned open
  // state while still allowing the disclosure's contents to update normally.
  preserveOpen(event) {
    if (event.detail.attributeName === "open") event.preventDefault();
  }

  get storageKey() {
    return `disclosure:${this.keyValue}`;
  }

  get storedState() {
    try {
      return localStorage.getItem(this.storageKey);
    } catch (_error) {
      return null;
    }
  }

  persistState() {
    try {
      localStorage.setItem(this.storageKey, String(this.element.open));
    } catch (_error) {
      // Storage can be unavailable in private or locked-down browsing.
    }
  }
}
