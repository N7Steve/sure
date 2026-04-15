import { Controller } from "@hotwired/stimulus"
import { computePosition, autoUpdate, offset, flip, shift } from "@floating-ui/dom"

// Connects to data-controller="autocomplete"
export default class extends Controller {
  static targets = ["input", "results", "account"]
  static values = { url: String }

  connect() {
    this.selectedIndex = -1
    this.cleanup = null
    
    // Hide initially
    this.resultsTarget.classList.add("hidden")
    // Use absolute strategy for floating UI
    Object.assign(this.resultsTarget.style, { position: "absolute", zIndex: "9999" })
  }

  disconnect() {
    if (this.cleanup) {
      this.cleanup()
      this.cleanup = null
    }
  }

  get accountId() {
    if (this.hasAccountTarget) {
      return this.accountTarget.value
    }
    return null
  }

  async fetch(event) {
    const query = this.inputTarget.value.trim()
    const accountId = this.accountId

    if (query.length === 0 || !accountId) {
      this.hide()
      return
    }

    // Basic debounce using a simple timeout
    clearTimeout(this.timeout)
    this.timeout = setTimeout(async () => {
      try {
        const url = new URL(this.urlValue, window.location.origin)
        url.searchParams.append("account_id", accountId)
        url.searchParams.append("q", query)

        const response = await fetch(url.toString(), {
          headers: { "Accept": "application/json" }
        })

        if (!response.ok) throw new Error("Network response was not ok")
        
        const descriptions = await response.json()
        this.renderResults(descriptions)
      } catch (error) {
        console.error("Autocomplete fetch error:", error)
        this.hide()
      }
    }, 200) // 200ms debounce
  }

  renderResults(descriptions) {
    if (descriptions.length === 0) {
      this.hide()
      return
    }

    this.resultsTarget.innerHTML = ""
    this.selectedIndex = -1

    descriptions.forEach((desc, index) => {
      const item = document.createElement("div")
      item.classList.add("px-4", "py-2", "cursor-pointer", "hover:bg-slate-100", "dark:hover:bg-slate-800", "truncate")
      item.textContent = desc
      item.dataset.index = index
      item.dataset.action = "click->autocomplete#select mousedown->autocomplete#preventBlur"
      this.resultsTarget.appendChild(item)
    })

    this.show()
  }

  hide() {
    this.resultsTarget.classList.add("hidden")
    if (this.cleanup) {
      this.cleanup()
      this.cleanup = null
    }
  }

  show() {
    this.resultsTarget.classList.remove("hidden")
    
    // Setup floating UI
    if (!this.cleanup) {
      this.cleanup = autoUpdate(
        this.inputTarget,
        this.resultsTarget,
        () => {
          computePosition(this.inputTarget, this.resultsTarget, {
            placement: 'bottom-start',
            strategy: 'absolute',
            middleware: [offset(4), flip(), shift({padding: 8})]
          }).then(({x, y}) => {
            Object.assign(this.resultsTarget.style, {
              left: `${x}px`,
              top: `${y}px`,
              width: `${this.inputTarget.offsetWidth}px`,
            })
          })
        }
      )
    }
  }

  preventBlur(event) {
    // Prevent the input from losing focus when clicking a result
    event.preventDefault()
  }

  select(event) {
    const item = event.currentTarget
    this.inputTarget.value = item.textContent
    this.hide()
    
    // Trigger a change event so other controllers know it updated
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }))
    this.inputTarget.focus()
  }

  keydown(event) {
    if (this.resultsTarget.classList.contains("hidden")) return

    const items = Array.from(this.resultsTarget.children)
    
    switch(event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
        this.highlightItem(items)
        break
      case "ArrowUp":
        event.preventDefault()
        this.selectedIndex = Math.max(this.selectedIndex - 1, -1)
        this.highlightItem(items)
        break
      case "Enter":
        if (this.selectedIndex >= 0) {
          event.preventDefault()
          this.inputTarget.value = items[this.selectedIndex].textContent
          this.hide()
          this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }))
        }
        break
      case "Escape":
        event.preventDefault()
        this.hide()
        break
    }
  }

  highlightItem(items) {
    items.forEach((item, index) => {
      if (index === this.selectedIndex) {
        item.classList.add("bg-slate-100", "dark:bg-slate-800")
      } else {
        item.classList.remove("bg-slate-100", "dark:bg-slate-800")
      }
    })
  }
}
