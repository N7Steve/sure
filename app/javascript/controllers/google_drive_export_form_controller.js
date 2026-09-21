import { Controller } from "@hotwired/stimulus";

// Keeps the schedule form focused on the fields relevant to the selected
// date range and cadence, and submits the browser's local IANA time zone.
export default class extends Controller {
  static targets = [
    "exportFormat",
    "transactionField",
    "dateRange",
    "dateRangeField",
    "frequency",
    "frequencyField",
    "timezoneInput",
    "timezoneLabel",
  ];

  static values = { timezoneTemplate: String };

  connect() {
    this.toggleExportFormatFields();
    this.toggleDateRangeFields();
    this.toggleFrequencyFields();
    this.applyBrowserTimezone();
  }

  toggleExportFormatFields() {
    if (!this.hasExportFormatTarget) return;

    const snapshotSelected = this.exportFormatTarget.value === "snapshot";
    this.transactionFieldTargets.forEach((field) => {
      field.classList.toggle("hidden", snapshotSelected);
      field.querySelectorAll("input, select, textarea").forEach((control) => {
        control.disabled = snapshotSelected;
      });
    });

    if (!snapshotSelected) this.toggleDateRangeFields();
  }

  toggleDateRangeFields() {
    if (!this.hasDateRangeTarget) return;

    if (
      this.hasExportFormatTarget &&
      this.exportFormatTarget.value === "snapshot"
    ) {
      this.dateRangeFieldTargets.forEach((field) => {
        field.querySelectorAll("input, select").forEach((control) => {
          control.disabled = true;
          if (control.dataset.conditionalRequired === "true") {
            control.required = false;
          }
        });
      });
      return;
    }

    this.toggleConditionalFields(
      this.dateRangeFieldTargets,
      "dateRange",
      this.dateRangeTarget.value,
    );
  }

  toggleFrequencyFields() {
    if (!this.hasFrequencyTarget) return;

    this.toggleConditionalFields(
      this.frequencyFieldTargets,
      "frequency",
      this.frequencyTarget.value,
    );
  }

  applyBrowserTimezone() {
    if (!this.hasTimezoneInputTarget) return;

    const timezone = this.browserTimezone();
    if (!timezone) return;

    this.timezoneInputTarget.value = timezone;
    if (this.hasTimezoneLabelTarget && this.hasTimezoneTemplateValue) {
      this.timezoneLabelTarget.textContent = this.timezoneTemplateValue.replace(
        "__TIMEZONE__",
        timezone,
      );
    }
  }

  browserTimezone() {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone;
    } catch {
      return null;
    }
  }

  toggleConditionalFields(fields, dataKey, selectedValue) {
    fields.forEach((field) => {
      const visible = field.dataset[dataKey] === selectedValue;
      field.classList.toggle("hidden", !visible);
      field.querySelectorAll("input, select").forEach((control) => {
        control.disabled = !visible;
        if (control.dataset.conditionalRequired === "true") {
          control.required = visible;
        }
      });
    });
  }
}
