import { Controller } from "@hotwired/stimulus";
import { reloadFrame } from "utils/reload_frame";

export default class extends Controller {
  connect() {
    document
      .querySelectorAll('turbo-frame[data-sync-refresh="sidebar"]')
      .forEach((frame) => reloadFrame(frame, frame.dataset.syncRefreshUrl));
  }
}
