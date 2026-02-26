import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener('mousedown', this.toggleOption);
    this.element.addEventListener('change', this.renderChips);

    // Create container for chips
    this.chipsContainer = document.createElement('div');
    this.chipsContainer.className = "flex flex-wrap gap-2 mt-2";
    this.element.parentNode.insertBefore(this.chipsContainer, this.element.nextSibling);

    // Initial render
    this.renderChips();
  }

  disconnect() {
    this.element.removeEventListener('mousedown', this.toggleOption);
    this.element.removeEventListener('change', this.renderChips);
    if (this.chipsContainer) {
      this.chipsContainer.remove();
    }
  }

  toggleOption = (e) => {
    const option = e.target;
    if (option.tagName === 'OPTION') {
      e.preventDefault();
      option.selected = !option.selected;
      const event = new Event('change', { bubbles: true });
      this.element.dispatchEvent(event);
    }
  }

  renderChips = () => {
    if (!this.chipsContainer) return;

    this.chipsContainer.innerHTML = '';

    const selectedOptions = Array.from(this.element.options).filter(opt => opt.selected && opt.value !== "");

    selectedOptions.forEach(option => {
      const chip = document.createElement('div');
      chip.className = "inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium bg-surface-inset text-primary border border-secondary shadow-sm";

      const removeBtn = document.createElement('button');
      removeBtn.type = "button";
      removeBtn.className = "text-secondary hover:text-primary focus:outline-none flex items-center justify-center";
      removeBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>`;

      removeBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        option.selected = false;
        const event = new Event('change', { bubbles: true });
        this.element.dispatchEvent(event);
      });

      const textSpan = document.createElement('span');
      textSpan.textContent = option.text;

      chip.appendChild(removeBtn);
      chip.appendChild(textSpan);

      this.chipsContainer.appendChild(chip);
    });
  }
}