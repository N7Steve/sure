class FamilyExport < ApplicationRecord
  # See Import::STUCK_AFTER — same dead-worker failure mode. Exports build in
  # minutes, so a shorter window; a wedged pending/processing export otherwise
  # spins in the UI forever (the exports index polls while any is in flight).
  STUCK_AFTER = 2.hours

  belongs_to :family
  belongs_to :requested_by, class_name: "User", optional: true

  has_one_attached :export_file, dependent: :purge_later

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  enum :export_type, {
    full_backup: "full_backup",
    transactions_csv: "transactions_csv"
  }, default: :full_backup, validate: true

  validate :validate_transaction_export_options, if: :transactions_csv?
  validate :selected_accounts_are_accessible, if: :transactions_csv?
  validate :requested_by_belongs_to_family, if: -> { requested_by.present? }

  scope :ordered, -> { order(created_at: :desc) }

  # See Import::PRESUMED_LOST_AFTER — same dead-worker failure mode. Exports
  # build in minutes; a pending/processing export idle for an hour is lost.
  PRESUMED_LOST_AFTER = 1.hour

  def presumed_lost?
    (pending? || processing?) && updated_at < PRESUMED_LOST_AFTER.ago
  end

  # Escape hatch for exports whose background job died mid-flight; the
  # with_lock re-check means a job finishing between render and click wins.
  # Export generation is in-memory, so nothing is left behind — the user
  # simply creates a new export.
  def force_fail!
    with_lock do
      return false unless presumed_lost?

      update!(status: :failed)
    end

    true
  end

  def self.clean
    where(status: [ :pending, :processing ])
      .where("updated_at < ?", STUCK_AFTER.ago)
      .includes(:family)
      .find_each do |export|
        # Read before the lock — see Import.reap_stuck!.
        family = export.family

        # Row-lock + staleness re-check before mutating, as Sync#perform
        # does since #2680 — the export job may have finished in between.
        export.with_lock do
          next unless %w[pending processing].include?(export.status) && export.updated_at < STUCK_AFTER.ago

          previous_status = export.status
          export.update!(status: :failed)

          DebugLogEntry.capture(
            category: "background_jobs",
            level: "warn",
            message: "Reaped FamilyExport stuck in #{previous_status} for over #{STUCK_AFTER.inspect}",
            source: name,
            family: family,
            metadata: { record_type: name, record_id: export.id, previous_status: previous_status, new_status: "failed" }
          )
        end
      rescue => e
        # One bad record must not abort the sweep for the rest.
        Rails.logger.error("FamilyExport.clean failed for #{export.id}: #{e.class}: #{e.message}")
        Sentry.capture_exception(e) { |scope| scope.set_tags(record_type: name, record_id: export.id) } if defined?(Sentry)
      end
  end

  def filename
    if transactions_csv?
      "transactions_#{start_date.strftime('%Y-%m-%d')}_to_#{end_date.strftime('%Y-%m-%d')}.csv"
    else
      "sure_export_#{created_at.strftime('%Y%m%d_%H%M%S')}.zip"
    end
  end

  def downloadable?
    completed? && export_file.attached?
  end

  def selected_account_ids
    filter_values("account_ids")
  end

  def excluded_category_ids
    filter_values("excluded_category_ids")
  end

  def excluded_tag_ids
    filter_values("excluded_tag_ids")
  end

  private
    def validate_transaction_export_options
      errors.add(:requested_by, :blank) if requested_by.blank?
      errors.add(:start_date, :blank) if start_date.blank?
      errors.add(:end_date, :blank) if end_date.blank?
      errors.add(:end_date, :before_start_date) if start_date.present? && end_date.present? && end_date < start_date
      errors.add(:filters, :accounts_required) if selected_account_ids.empty?
    end

    def requested_by_belongs_to_family
      errors.add(:requested_by, :invalid) unless requested_by.family_id == family_id
    end

    def selected_accounts_are_accessible
      return if requested_by.blank? || selected_account_ids.empty?

      selected_ids = selected_account_ids.map(&:to_s)
      accessible_ids = requested_by.accessible_accounts.where(id: selected_ids).pluck(:id).map(&:to_s)
      errors.add(:filters, :invalid_accounts) if (selected_ids - accessible_ids).any?
    end

    def filter_values(key)
      Array(filters&.[](key) || filters&.[](key.to_sym)).compact_blank
    end
end
