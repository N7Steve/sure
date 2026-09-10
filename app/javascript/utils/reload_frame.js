export function reloadFrame(frame, url = window.location.href) {
  const destination = new URL(url, window.location.href);
  if (destination.origin !== window.location.origin) return;

  if (frame.src === destination.href) {
    frame.reload();
  } else {
    frame.src = destination.href;
  }
}
