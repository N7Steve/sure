class DispatchGoogleDriveExportsJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    GoogleDriveExportSchedule.due.find_each do |schedule|
      schedule.with_lock do
        schedule.reload
        next unless schedule.active? && schedule.next_run_at <= Time.current

        schedule.update!(next_run_at: schedule.next_occurrence_after(Time.current))
        GoogleDriveExportJob.perform_later(schedule, triggered_by: "scheduled")
      end
    rescue => e
      DebugLogEntry.capture(
        category: "background_jobs",
        level: "error",
        message: "Could not dispatch a Google Drive export: #{e.class}",
        source: self.class.name,
        provider_key: "google_drive",
        family: schedule.family,
        user: schedule.user,
        metadata: { schedule_id: schedule.id }
      )
    end
  end
end
