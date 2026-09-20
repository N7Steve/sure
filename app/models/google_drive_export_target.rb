class GoogleDriveExportTarget < ApplicationRecord
  belongs_to :google_drive_export_schedule, inverse_of: :targets
  has_many :runs, class_name: "GoogleDriveExportRun", dependent: :nullify, inverse_of: :google_drive_export_target

  validates :logical_key, presence: true, uniqueness: { scope: :google_drive_export_schedule_id }

  delegate :family, :user, to: :google_drive_export_schedule
end
