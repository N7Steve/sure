const DURATION = 200;
const EASING = "ease-out";
const activeAnimations = new WeakMap();

export function setCollapsibleState({
  container,
  content,
  chevron,
  expanded,
  animate = true,
}) {
  const startHeight = container.getBoundingClientRect().height;
  cancelActiveAnimation(container, content);

  chevron.classList.toggle("-rotate-90", !expanded);

  if (!animate || prefersReducedMotion()) {
    content.classList.toggle("hidden", !expanded);
    return;
  }

  content.classList.remove("hidden");
  const endHeight = expanded
    ? container.getBoundingClientRect().height
    : heightWithoutContent(container, content);

  container.style.overflow = "hidden";
  const heightAnimation = container.animate(
    { height: [`${startHeight}px`, `${endHeight}px`] },
    { duration: DURATION, easing: EASING },
  );
  const contentAnimation = content.animate(
    { opacity: expanded ? [0, 1] : [1, 0] },
    { duration: DURATION, easing: EASING },
  );
  const state = { heightAnimation, contentAnimation };
  activeAnimations.set(container, state);

  heightAnimation.onfinish = () => {
    if (activeAnimations.get(container) !== state) return;

    if (!expanded) content.classList.add("hidden");
    cleanup(container, content, state);
  };
}

function heightWithoutContent(container, content) {
  content.classList.add("hidden");
  const height = container.getBoundingClientRect().height;
  content.classList.remove("hidden");
  return height;
}

function cancelActiveAnimation(container, content) {
  const active = activeAnimations.get(container);
  if (!active) return;

  active.heightAnimation.cancel();
  active.contentAnimation.cancel();
  cleanup(container, content, active);
}

function cleanup(container, content, state) {
  state.contentAnimation.cancel();
  container.style.height = "";
  container.style.overflow = "";
  content.style.opacity = "";
  activeAnimations.delete(container);
}

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}
