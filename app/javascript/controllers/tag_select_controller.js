import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  connect() {
    this.element.style.display = "none";

    this.wrapper = document.createElement('div');
    this.wrapper.className = "relative";
    this.element.parentNode.insertBefore(this.wrapper, this.element.nextSibling);

    this.trigger = document.createElement('button');
    this.trigger.type = 'button';
    this.trigger.className = "form-field__input w-full text-left cursor-pointer";
    this.trigger.addEventListener('click', this.toggleDropdown);
    this.wrapper.appendChild(this.trigger);

    this.dropdown = document.createElement('div');
    this.dropdown.className = "absolute z-50 p-1.5 w-full min-w-32 rounded-lg shadow-lg bg-container mt-1.5 transition duration-150 ease-out hidden";
    this.dropdown.style.cssText = "border: 1px solid var(--color-alpha-white-200);";
    this.wrapper.appendChild(this.dropdown);

    this.filterInput = document.createElement('input');
    this.filterInput.type = 'search';
    this.filterInput.placeholder = 'Search tags...';
    this.filterInput.className = "form-field__input text-sm mb-2 w-full";
    this.filterInput.addEventListener('input', this.filterOptions);
    this.dropdown.appendChild(this.filterInput);

    this.optionsList = document.createElement('div');
    this.optionsList.className = "flex flex-col gap-0.5 max-h-48 overflow-auto";
    this.dropdown.appendChild(this.optionsList);

    this.chipsContainer = document.createElement('div');
    this.chipsContainer.className = "flex flex-wrap gap-2 mt-2 hidden";
    this.wrapper.appendChild(this.chipsContainer);

    this.buildOptions();
    this.updateTriggerText();
    this.renderChips();

    this._outsideClickHandler = (e) => {
      if (!this.wrapper.contains(e.target) && !this.element.contains(e.target)) {
        this.closeDropdown();
      }
    };
    document.addEventListener('click', this._outsideClickHandler);
  }

  disconnect() {
    document.removeEventListener('click', this._outsideClickHandler);
    if (this.wrapper) this.wrapper.remove();
    this.element.style.display = "";
  }

  buildOptions = () => {
    this.optionsList.innerHTML = '';
    Array.from(this.element.options).forEach(option => {
      if (option.value === "") return;

      const item = document.createElement('div');
      item.className = "filterable-item text-primary text-sm cursor-pointer flex items-center gap-2 py-2 px-3 rounded-lg hover:bg-container-inset-hover";
      item.dataset.value = option.value;
      item.dataset.filterName = option.text;

      const check = document.createElement('span');
      check.className = option.selected ? "check-icon" : "check-icon hidden";
      check.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>`;

      const label = document.createElement('span');
      label.textContent = option.text;

      item.appendChild(check);
      item.appendChild(label);

      item.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        option.selected = !option.selected;
        check.classList.toggle('hidden', !option.selected);
        item.classList.toggle('bg-container-inset', option.selected);
        this.updateTriggerText();
        this.renderChips();
        const event = new Event('change', { bubbles: true });
        this.element.dispatchEvent(event);
      });

      if (option.selected) {
        item.classList.add('bg-container-inset');
      }

      this.optionsList.appendChild(item);
    });
  }

  toggleDropdown = (e) => {
    e.preventDefault();
    e.stopPropagation();
    const isHidden = this.dropdown.classList.contains('hidden');
    if (isHidden) {
      this.dropdown.classList.remove('hidden');
      this.filterInput.value = '';
      this.filterOptions({ target: this.filterInput });
      this.filterInput.focus();
    } else {
      this.closeDropdown();
    }
  }

  closeDropdown = () => {
    this.dropdown.classList.add('hidden');
  }

  filterOptions = (e) => {
    const term = e.target.value.toLowerCase();
    this.optionsList.querySelectorAll('.filterable-item').forEach(item => {
      const name = (item.dataset.filterName || '').toLowerCase();
      item.style.display = name.includes(term) ? '' : 'none';
    });
  }

  updateTriggerText = () => {
    const selected = Array.from(this.element.options).filter(o => o.selected && o.value !== "");
    if (selected.length === 0) {
      this.trigger.textContent = this.element.querySelector('option[value=""]')?.text || '(none)';
      this.trigger.classList.add('text-secondary');
    } else {
      this.trigger.textContent = selected.map(o => o.text).join(', ');
      this.trigger.classList.remove('text-secondary');
    }
  }

  renderChips = () => {
    if (!this.chipsContainer) return;
    this.chipsContainer.innerHTML = '';

    const selectedOptions = Array.from(this.element.options).filter(opt => opt.selected && opt.value !== "");

    if (selectedOptions.length > 0) {
      this.chipsContainer.classList.remove('hidden');
    } else {
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
        const item = this.optionsList.querySelector(`[data-value="${option.value}"]`);
        if (item) {
          item.classList.remove('bg-container-inset');
          item.querySelector('.check-icon')?.classList.add('hidden');
        }
        this.updateTriggerText();
        this.renderChips();
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
