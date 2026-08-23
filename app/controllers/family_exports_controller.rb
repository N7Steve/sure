class FamilyExportsController < ApplicationController
  include StreamExtensions

  before_action :require_admin
  before_action :set_export, only: [ :download, :destroy, :cancel ]

  def new
    @export_type = params[:export_type].presence_in(FamilyExport.export_types.keys) || "full_backup"
    return require_admin if @export_type == "full_backup" && !Current.user.admin?

    @export = Current.family.family_exports.new(
      export_type: @export_type,
      requested_by: Current.user,
      start_date: 1.month.ago.to_date,
      end_date: Date.current
    )
    if @export.transactions_csv?
      prepare_transaction_export_options
      @export.filters = {
        "account_ids" => @accounts.map(&:id),
        "excluded_category_ids" => [],
        "excluded_tag_ids" => []
      }
    end
  end

  def create
    @export_type = family_export_params[:export_type].presence_in(FamilyExport.export_types.keys) || "full_backup"
    return require_admin if @export_type == "full_backup" && !Current.user.admin?

    @export = build_export

    unless @export.save
      prepare_transaction_export_options if @export.transactions_csv?
      render :new, status: :unprocessable_entity
      return
    end

    FamilyDataExportJob.perform_later(@export)

    respond_to do |format|
      format.html { redirect_to family_exports_path, notice: t("family_exports.create.success") }
      format.turbo_stream {
        stream_redirect_to family_exports_path, notice: t("family_exports.create.success")
      }
    end
  end

  def index
    @pagy, @exports = pagy(visible_exports.ordered, limit: safe_per_page)
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.exports"), family_exports_path ]
    ]

    respond_to do |format|
      format.html { render layout: "settings" }
      format.turbo_stream { redirect_to family_exports_path }
    end
  end

  def download
    if @export.downloadable?
      redirect_to rails_blob_path(@export.export_file, disposition: "attachment"), allow_other_host: true
    else
      redirect_to family_exports_path, alert: t("family_exports.export_not_ready")
    end
  end

  def destroy
    @export.destroy
    redirect_to family_exports_path, notice: t("family_exports.destroy.success")
  end

  def cancel
    if @export.force_fail!
      redirect_to family_exports_path, notice: t(".cancelled")
    else
      redirect_to family_exports_path, alert: t(".not_cancellable")
    end
  end

  private

    def set_export
      @export = visible_exports.find(params[:id])
    end

    def require_admin
      redirect_to root_path, alert: t("family_exports.access_denied")
    end

    def visible_exports
      base_scope = Current.family.family_exports
      own_transaction_exports = base_scope.where(
        export_type: "transactions_csv",
        requested_by_id: Current.user.id
      )

      return own_transaction_exports unless Current.user.admin?

      base_scope.where(export_type: "full_backup").or(own_transaction_exports)
    end

    def family_export_params
      params.fetch(:family_export, ActionController::Parameters.new).permit(
        :export_type,
        :start_date,
        :end_date,
        filters: {
          account_ids: [],
          excluded_category_ids: [],
          excluded_tag_ids: []
        }
      )
    end

    def build_export
      if @export_type == "transactions_csv"
        permitted = family_export_params
        Current.family.family_exports.new(
          export_type: @export_type,
          requested_by: Current.user,
          start_date: permitted[:start_date],
          end_date: permitted[:end_date],
          filters: normalize_filters(permitted[:filters])
        )
      else
        Current.family.family_exports.new(
          export_type: "full_backup",
          requested_by: Current.user
        )
      end
    end

    def normalize_filters(raw_filters)
      filters = raw_filters || {}
      {
        "account_ids" => Array(filters[:account_ids]).compact_blank.uniq,
        "excluded_category_ids" => Array(filters[:excluded_category_ids]).compact_blank.uniq,
        "excluded_tag_ids" => Array(filters[:excluded_tag_ids]).compact_blank.uniq
      }
    end

    def prepare_transaction_export_options
      @accounts = Current.user.accessible_accounts.sidebar_visible.not_excluded.alphabetically
      @categories = Current.family.categories.includes(:parent).order(:name)
      @tags = Current.family.tags.alphabetically
    end
end
