class GoogleDriveExportRun < ApplicationRecord
  belongs_to :google_drive_export_schedule, inverse_of: :runs
  belongs_to :google_drive_export_target, optional: true, inverse_of: :runs

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  enum :triggered_by, {
    scheduled: "scheduled",
    manual: "manual",
    initial: "initial"
  }, default: :scheduled, validate: true, prefix: true

  validates :error_message, length: { maximum: 1_000 }, allow_nil: true
end
