import { Controller } from "@hotwired/stimulus";
import { reloadFrame } from "utils/reload_frame";

// Connects to data-controller="sync-toast"
//
// Shown when a background sync completes and the family's data has changed.
// - Scoped data frame → reloads only that frame after a short delay.
// - Account page      → its account broadcast owns the scoped refresh.
// - Other idle page   → morph-refreshes the page after a short delay.
// - Mid-form          → stays put; the user refreshes when ready.
// - A modal <dialog> is open → the toast is deferred (it would otherwise sit
//   dimmed-but-clickable behind the dialog's top-layer backdrop, and a refresh
//   would close the dialog and discard its in-progress input). It is revealed
//   once the dialog closes — the first moment a refresh is actually safe.
export default class extends Controller {
  static values = {
    autoRefreshDelay: { type: Number, default: 2000 },
  };

  connect() {
    // Account pages receive their own account-scoped frame refresh from the
    // sync completion event. A second family-level visit would be redundant.
    if (document.querySelector('turbo-frame[data-sync-refresh="account"]')) {
      this.element.remove();
      return;
    }

    if (this.#dialogOpen()) {
      this.#deferUntilDialogCloses();
      return;
    }
    this.#arm();
  }

  disconnect() {
    clearTimeout(this._timer);
    this.#removeDeferredDialogListener();
  }

  // Prefer a page-owned family frame. Other pages fall back to Turbo 8's
  // morph refresh, which preserves scroll and `data-turbo-permanent` elements.
  refresh() {
    clearTimeout(this._timer);

    const familyFrame = document.querySelector(
      'turbo-frame[data-sync-refresh="family"]',
    );
    if (familyFrame) {
      reloadFrame(familyFrame);
      this.element.remove();
      return;
    }

    Turbo.visit(window.location.href, { action: "replace" });
  }

  #arm() {
    if (this.#userIsInteracting()) return; // mid-form: wait for a manual refresh
    // Re-check at fire time, not just arm time: the post-dialog reveal often
    // lands on a form the dialog was sitting on, and the user resumes typing
    // inside this window (a morph would wipe their non-turbo-permanent
    // input). A dialog opened during the window is the same hazard — the
    // refresh would close it. Either way, bail and leave the toast visible
    // for a manual refresh, matching the mid-form behavior.
    this._timer = setTimeout(() => {
      if (this.#userIsInteracting() || this.#dialogOpen()) return;
      this.refresh();
    }, this.autoRefreshDelayValue);
  }

  #deferUntilDialogCloses() {
    this.element.style.display = "none";
    const dialog = document.querySelector("dialog[open]");
    if (!dialog) {
      this.#reveal();
      return;
    }
    // Keep refs so disconnect() can detach this listener. Otherwise a toast
    // replaced by a newer broadcast while the dialog is still open stays
    // subscribed, and its now-detached controller fires #reveal()/#arm() on
    // close — a spurious auto-refresh from a stale toast.
    //
    // Known edge: if this dialog leaves the DOM without firing `close` (e.g.
    // a morph removes it), the toast stays hidden until the next broadcast
    // replaces it. Acceptable: the next sync re-delivers the toast.
    this._deferredDialog = dialog;
    this._dialogCloseHandler = () => this.#onDialogClose();
    dialog.addEventListener("close", this._dialogCloseHandler, { once: true });
  }

  #onDialogClose() {
    // The `once` listener has already fired and detached itself.
    this._deferredDialog = null;
    this._dialogCloseHandler = null;
    // Another dialog may still be open (stacked modals) — keep deferring until
    // every dialog has closed.
    if (this.#dialogOpen()) {
      this.#deferUntilDialogCloses();
      return;
    }
    this.#reveal();
  }

  #removeDeferredDialogListener() {
    if (this._deferredDialog && this._dialogCloseHandler) {
      this._deferredDialog.removeEventListener(
        "close",
        this._dialogCloseHandler,
      );
    }
    this._deferredDialog = null;
    this._dialogCloseHandler = null;
  }

  #reveal() {
    this.element.style.display = "";
    this.#arm();
  }

  #dialogOpen() {
    return !!document.querySelector("dialog[open]");
  }

  #userIsInteracting() {
    const el = document.activeElement;
    if (!el || el === document.body || el === document.documentElement)
      return false;
    return (
      el.isContentEditable ||
      el.closest("form, dialog, [role='dialog']") !== null
    );
  }
}
