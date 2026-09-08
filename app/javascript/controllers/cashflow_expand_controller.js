import { Controller } from "@hotwired/stimulus";
import { openDialog } from "utils/dialog";

export default class extends Controller {
  open() {
    const dialog = this.element.querySelector("dialog");
    if (!dialog) return;

    if (typeof this.originalDraggable === "undefined") {
      this.originalDraggable = this.element.getAttribute("draggable");
    }
    this.element.setAttribute("draggable", "false");

    openDialog(this.application, dialog);
  }

  restore() {
    if (this.originalDraggable === undefined) return;
    this.originalDraggable
      ? this.element.setAttribute("draggable", this.originalDraggable)
      : this.element.removeAttribute("draggable");
    this.originalDraggable = undefined;
  }
}
