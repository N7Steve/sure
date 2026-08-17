class FamilyDataExportJob < ApplicationJob
  queue_as :default

  def perform(family_export)
    # Terminal statuses own the record: a redelivered job must not restart a
    # completed export, and one the reaper already failed stays failed.
    # A processing export is allowed through — graceful worker shutdowns
    # re-enqueue in-flight jobs, and that redelivery is what completes it.
    return if family_export.completed? || family_export.failed?

    family_export.update!(status: :processing)

    if family_export.transactions_csv?
      result = Family::TransactionCsvExporter.new(family_export).generate
      export_file = result.io
      content_type = "text/csv; charset=utf-8"
      family_export.record_count = result.record_count
    else
      exporter = Family::DataExporter.new(family_export.family)
      export_file = exporter.generate_export
      content_type = "application/zip"
    end

    family_export.export_file.attach(
      io: export_file,
      filename: family_export.filename,
      content_type: content_type
    )

    family_export.update!(status: :completed, record_count: family_export.record_count)
  rescue => e
    Rails.logger.error "Family export failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    family_export.update!(status: :failed)
  end
end
