class GoogleDriveExportSchedulesController < ApplicationController
  include StreamExtensions

  before_action :set_connection
  before_action :set_schedule, only: [ :edit, :update, :destroy, :run_now ]
  before_action :prepare_options, only: [ :new, :create, :edit, :update ]

  def new
    timezone = Current.family.timezone.presence || "UTC"
    local_date = Time.current.in_time_zone(timezone).to_date
    @schedule = @connection.export_schedules.new(
      family: Current.family,
      user: Current.user,
      timezone: timezone,
      run_at: "06:00",
      weekday: local_date.wday,
      day_of_month: local_date.day,
      filters: default_filters
    )
  end

  def create
    @schedule = @connection.export_schedules.new(schedule_attributes)
    @schedule.family = Current.family
    @schedule.user = Current.user

    if @schedule.save
      GoogleDriveExportJob.perform_later(@schedule, triggered_by: "initial")
      redirect_after_save(t("google_drive_export_schedules.create.success"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @schedule.assign_attributes(schedule_attributes)
    @schedule.next_run_at = @schedule.next_occurrence_after(Time.current) if schedule_timing_valid?

    if @schedule.save
      redirect_after_save(t("google_drive_export_schedules.update.success"))
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @schedule.destroy!
    redirect_to family_exports_path, notice: t("google_drive_export_schedules.destroy.success")
  end

  def run_now
    GoogleDriveExportJob.perform_later(@schedule, triggered_by: "manual")
    redirect_to family_exports_path, notice: t("google_drive_export_schedules.run_now.success")
  end

  private
    def set_connection
      @connection = Current.user.google_drive_connection
      return if @connection&.connected?

      redirect_to family_exports_path, alert: t("google_drive_export_schedules.connection_required")
    end

    def set_schedule
      @schedule = @connection.export_schedules.where(family: Current.family, user: Current.user).find(params[:id])
    end

    def prepare_options
      @accounts = Current.user.accessible_accounts.visible.alphabetically
      @categories = Current.family.categories.includes(:parent).order(:name)
      @tags = Current.family.tags.alphabetically
    end

    def schedule_params
      params.require(:google_drive_export_schedule).permit(
        :name,
        :filename,
        :status,
        :frequency,
        :run_at,
        :weekday,
        :day_of_month,
        :timezone,
        :date_range,
        :fixed_start_date,
        :rolling_days,
        filters: {
          account_ids: [],
          excluded_category_ids: [],
          excluded_tag_ids: []
        }
      )
    end

    def schedule_attributes
      permitted = schedule_params
      permitted[:filters] = normalize_filters(permitted[:filters])
      permitted
    end

    def normalize_filters(filters)
      values = filters || {}
      {
        "account_ids" => Array(values[:account_ids]).compact_blank.uniq,
        "excluded_category_ids" => Array(values[:excluded_category_ids]).compact_blank.uniq,
        "excluded_tag_ids" => Array(values[:excluded_tag_ids]).compact_blank.uniq
      }
    end

    def default_filters
      {
        "account_ids" => @accounts.map { |account| account.id.to_s },
        "excluded_category_ids" => [],
        "excluded_tag_ids" => []
      }
    end

    def schedule_timing_valid?
      @schedule.run_at.present? && ActiveSupport::TimeZone[@schedule.timezone].present? &&
        (!@schedule.weekly? || @schedule.weekday.present?) &&
        (!@schedule.monthly? || @schedule.day_of_month.present?)
    end

    def redirect_after_save(notice)
      respond_to do |format|
        format.html { redirect_to family_exports_path, notice: notice }
        format.turbo_stream { stream_redirect_to family_exports_path, notice: notice }
      end
    end
end
