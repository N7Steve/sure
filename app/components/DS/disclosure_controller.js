import { Controller } from "@hotwired/stimulus";

const DURATION = 200;
const EASING = "ease-out";

export default class extends Controller {
  static targets = ["content"];

  connect() {
    this.isClosing = false;
    this.summary = this.element.querySelector(":scope > summary");
    this.boundToggle = this.toggle.bind(this);
    this.summary?.addEventListener("click", this.boundToggle);
  }

  disconnect() {
    this.summary?.removeEventListener("click", this.boundToggle);
    this.cancelAnimations();
  }

  toggle(event) {
    event.preventDefault();

    if (this.prefersReducedMotion) {
      this.element.open = !this.element.open;
      return;
    }

    this.isClosing || !this.element.open ? this.expand() : this.collapse();
  }

  expand() {
    const startHeight = this.element.offsetHeight;
    this.cancelAnimations();
    this.isClosing = false;
    this.element.open = true;
    const endHeight = this.element.offsetHeight;

    this.animateHeight(startHeight, endHeight, true);
    this.animateContent(0, 1);
  }

  collapse() {
    const startHeight = this.element.offsetHeight;
    const endHeight = this.summary.offsetHeight;

    this.cancelAnimations();
    this.isClosing = true;
    this.animateHeight(startHeight, endHeight, false);
    this.animateContent(1, 0);
  }

  animateHeight(startHeight, endHeight, open) {
    this.element.style.overflow = "hidden";
    this.heightAnimation = this.element.animate(
      { height: [`${startHeight}px`, `${endHeight}px`] },
      { duration: DURATION, easing: EASING },
    );
    this.heightAnimation.onfinish = () => this.finish(open);
  }

  animateContent(startOpacity, endOpacity) {
    if (!this.hasContentTarget) return;

    this.contentAnimation = this.contentTarget.animate(
      { opacity: [startOpacity, endOpacity] },
      { duration: DURATION, easing: EASING },
    );
  }

  finish(open) {
    this.element.open = open;
    this.isClosing = false;
    this.heightAnimation = null;
    this.contentAnimation?.cancel();
    this.contentAnimation = null;
    this.element.style.height = "";
    this.element.style.overflow = "";
  }

  cancelAnimations() {
    this.heightAnimation?.cancel();
    this.contentAnimation?.cancel();
    this.heightAnimation = null;
    this.contentAnimation = null;
    this.element.style.height = "";
    this.element.style.overflow = "";
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  }
}
