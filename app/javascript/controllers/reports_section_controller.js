import { Controller } from "@hotwired/stimulus";
import { setCollapsibleState } from "utils/collapsible_animation";

export default class extends Controller {
  static targets = ["content", "chevron", "button"];
  static values = {
    sectionKey: String,
    collapsed: Boolean,
  };

  connect() {
    if (this.collapsedValue) {
      this.collapse(false, false);
    }
  }

  toggle(event) {
    event.preventDefault();
    if (this.collapsedValue) {
      this.expand();
    } else {
      this.collapse();
    }
  }

  handleToggleKeydown(event) {
    // Handle Enter and Space keys for keyboard accessibility
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      event.stopPropagation(); // Prevent section's keyboard handler from firing
      this.toggle(event);
    }
  }

  collapse(persist = true, animate = true) {
    setCollapsibleState({
      container: this.element,
      content: this.contentTarget,
      chevron: this.chevronTarget,
      expanded: false,
      animate,
    });
    this.collapsedValue = true;
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "false");
    }
    if (persist) {
      this.savePreference(true);
    }
  }

  expand() {
    setCollapsibleState({
      container: this.element,
      content: this.contentTarget,
      chevron: this.chevronTarget,
      expanded: true,
    });
    this.collapsedValue = false;
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", "true");
    }
    this.savePreference(false);
  }

  async savePreference(collapsed) {
    const preferences = {
      reports_collapsed_sections: {
        [this.sectionKeyValue]: collapsed,
      },
    };

    // Safely obtain CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]');
    if (!csrfToken) {
      console.error(
        "[Reports Section] CSRF token not found. Cannot save preferences.",
      );
      return;
    }

    try {
      const response = await fetch("/reports/update_preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken.content,
        },
        body: JSON.stringify({ preferences }),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        console.error(
          "[Reports Section] Failed to save preferences:",
          response.status,
          errorData,
        );
      }
    } catch (error) {
      console.error(
        "[Reports Section] Network error saving preferences:",
        error,
      );
    }
  }
}
