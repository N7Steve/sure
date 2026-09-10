import { Controller } from "@hotwired/stimulus";
import { reloadFrame } from "utils/reload_frame";

export default class extends Controller {
  static values = { url: String };

  connect() {
    const frame = this.element.closest("turbo-frame");
    if (!frame) return;

    reloadFrame(frame, this.hasUrlValue ? this.urlValue : window.location.href);
  }
}
