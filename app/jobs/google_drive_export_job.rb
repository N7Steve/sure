require "digest"

class GoogleDriveExportJob < ApplicationJob
  queue_as :default
  sidekiq_options lock: :until_executed,
                  lock_args: ->(args) { [ args.first ] },
                  on_conflict: :log

  def perform(schedule, triggered_by: "scheduled")
    return if triggered_by == "scheduled" && !schedule.active?

    run = schedule.runs.create!(status: :processing, triggered_by: triggered_by, started_at: Time.current)
    execute(schedule, run)
  rescue GoogleDrive::Client::AuthenticationError => e
    connection = schedule.google_drive_connection
    connection.update!(status: :requires_reauthorization)
    connection.export_schedules.where(status: :active).update_all(
      status: "needs_attention",
      last_error_code: "reauthorization_required",
      updated_at: Time.current
    )
    fail_permanently(schedule, run, e, "reauthorization_required")
  rescue GoogleDrive::Client::FileMissingError => e
    fail_permanently(schedule, run, e, "file_missing")
  rescue GoogleDrive::Client::PermissionError => e
    fail_permanently(schedule, run, e, "permission_denied")
  rescue ActiveRecord::RecordInvalid => e
    fail_permanently(schedule, run, e, "access_changed")
  rescue GoogleDrive::Client::TransientError => e
    fail_run(schedule, run, e, "transient_error")
    raise
  rescue => e
    fail_permanently(schedule, run, e, "export_failed")
  end

  private
    def execute(schedule, run)
      raise ActiveRecord::RecordInvalid, schedule unless schedule.valid?
      target = schedule.with_lock do
        schedule.targets.find_or_create_by!(logical_key: "transactions")
      end
      run.update!(google_drive_export_target: target)

      result = Family::TransactionCsvExporter.new(schedule, schema: :drive).generate
      content = result.io.read
      digest = Digest::SHA256.hexdigest(content)
      drive = GoogleDrive::Client.new(schedule.google_drive_connection)

      upload_result = target.with_lock do
        file, created = resolve_file(drive, schedule, target, content)
        unchanged = !created &&
          target.content_digest == digest &&
          target.provider_file_id.present? &&
          file["name"] == schedule.filename

        unless unchanged || created
          file = drive.update_file(file_id: file.fetch("id"), name: schedule.filename, content: content)
        end

        if file["trashed"]
          raise GoogleDrive::Client::FileMissingError, "The Google Drive export file is in the trash"
        end

        target.update!(
          provider_file_id: file.fetch("id"),
          web_view_link: file["webViewLink"],
          content_digest: digest,
          last_uploaded_at: unchanged ? target.last_uploaded_at : Time.current
        )
        unchanged ? "unchanged" : "uploaded"
      end

      now = Time.current
      run.update!(status: :completed, result: upload_result, record_count: result.record_count, finished_at: now)
      schedule.update!(
        last_run_at: now,
        last_success_at: now,
        last_error_code: nil,
        status: schedule.paused? ? :paused : :active
      )
    end

    def resolve_file(drive, schedule, target, content)
      if target.provider_file_id.present?
        return [ drive.get_file(file_id: target.provider_file_id), false ]
      end

      found = drive.find_file(schedule_id: schedule.id, logical_key: target.logical_key)
      return [ found, false ] if found

      [
        drive.create_file(
          name: schedule.filename,
          content: content,
          schedule_id: schedule.id,
          logical_key: target.logical_key
        ),
        true
      ]
    end

    def fail_permanently(schedule, run, error, code)
      schedule.update_columns(
        status: schedule.paused? ? "paused" : "needs_attention",
        last_run_at: Time.current,
        last_error_code: code,
        updated_at: Time.current
      )
      fail_run(schedule, run, error, code)
    end

    def fail_run(schedule, run, error, code)
      run&.update!(
        status: :failed,
        error_code: code,
        error_message: error.message.to_s.truncate(1_000),
        finished_at: Time.current
      )
      schedule.update_columns(last_run_at: Time.current, last_error_code: code, updated_at: Time.current)
      DebugLogEntry.capture(
        category: "provider_sync",
        level: "error",
        message: "Google Drive export failed: #{error.class}",
        source: self.class.name,
        provider_key: "google_drive",
        family: schedule.family,
        user: schedule.user,
        metadata: { schedule_id: schedule.id, run_id: run&.id, error_code: code }
      )
    rescue => logging_error
      Rails.logger.error("Could not record Google Drive export failure: #{logging_error.class}: #{logging_error.message}")
    end
end
