# Fork boundary for user-facing Bills endpoints. Controllers can keep their
# upstream routes and implementation while Agenda remains the only product UI.
module BillsFrontendGuardable
  extend ActiveSupport::Concern

  private
    def ensure_bills_frontend_enabled
      return if Rails.configuration.x.bills_frontend_enabled

      redirect_to scheduled_payments_path
    end
end
