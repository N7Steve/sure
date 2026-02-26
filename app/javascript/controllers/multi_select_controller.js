import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.addEventListener('mousedown', this.toggleOption);
    this.element.addEventListener('change', this.renderChips);

    // Create filter input
    this.filterInput = document.createElement('input');
    this.filterInput.type = 'text';
    this.filterInput.placeholder = 'Search tags...';
    this.filterInput.className = "form-field__input text-sm mb-2";
    this.filterInput.addEventListener('input', this.filterOptions);
    this.element.parentNode.insertBefore(this.filterInput, this.element);

    // Create separator
    this.separator = document.createElement('div');
    this.separator.className = "border-t border-secondary mt-3 mb-2 hidden";
    this.element.parentNode.insertBefore(this.separator, this.element.nextSibling);

    // Create container for chips
    this.chipsContainer = document.createElement('div');
    this.chipsContainer.className = "flex flex-wrap gap-2 mt-2";
    this.element.parentNode.insertBefore(this.chipsContainer, this.separator.nextSibling);

    // Initial render
    this.renderChips();
  }

  disconnect() {
    this.element.removeEventListener('mousedown', this.toggleOption);
    this.element.removeEventListener('change', this.renderChips);

    if (this.filterInput) {
      this.filterInput.removeEventListener('input', this.filterOptions);
      this.filterInput.remove();
    }

    if (this.separator) {
      this.separator.remove();
    }

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

  filterOptions = (e) => {
    const term = e.target.value.toLowerCase();
    Array.from(this.element.options).forEach(option => {
      if (option.value === "") return;

      const text = option.text.toLowerCase();
      if (text.includes(term)) {
        option.hidden = false;
        option.style.display = "";
      } else {
        option.hidden = true;
        option.style.display = "none";
      }
    });
  }

  renderChips = () => {
    if (!this.chipsContainer) return;

    this.chipsContainer.innerHTML = '';

    const selectedOptions = Array.from(this.element.options).filter(opt => opt.selected && opt.value !== "");

    if (selectedOptions.length > 0) {
      if (this.separator) this.separator.classList.remove('hidden');
      this.chipsContainer.classList.remove('hidden');
    } else {
      if (this.separator) this.separator.classList.add('hidden');
      this.chipsContainer.classList.add('hidden');
    }

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