class TransfersController < ApplicationController
  include StreamExtensions

  before_action :set_transfer, only: %i[show destroy update]
  before_action :set_accounts, only: %i[new create]

  def new
    @transfer = Transfer.new
    @from_account_id = params[:from_account_id]
  end

  def show
    @categories = Current.family.categories.alphabetically
  end

  def create
    # Validate user has write access to both accounts
    source_account = accessible_accounts.find(transfer_params[:from_account_id])
    destination_account = accessible_accounts.find(transfer_params[:to_account_id])

    return unless require_account_permission!(source_account, redirect_path: transactions_path)
    return unless require_account_permission!(destination_account, redirect_path: transactions_path)

    @transfer = Transfer::Creator.new(
      family: Current.family,
      source_account_id: source_account.id,
      destination_account_id: destination_account.id,
      date: transfer_params[:date].present? ? Date.parse(transfer_params[:date]) : Date.current,
      amount: transfer_params[:amount].to_d,
      exchange_rate: transfer_params[:exchange_rate].presence&.to_d,
      category_id: transfer_params[:category_id]
    ).create

    if @transfer.persisted?
      success_message = "Transfer created"
      respond_to do |format|
        format.html { redirect_back_or_to transactions_path, notice: success_message }
        format.turbo_stream { stream_redirect_back_or_to transactions_path, notice: success_message }
      end
    else
      @from_account_id = transfer_params[:from_account_id]
      render :new, status: :unprocessable_entity
    end
  rescue Money::ConversionError
    @transfer ||= Transfer.new
    @transfer.errors.add(:base, "Exchange rate unavailable for selected currencies and date")
    set_accounts
    render :new, status: :unprocessable_entity
  rescue ArgumentError
    @transfer ||= Transfer.new
    @transfer.errors.add(:date, "is invalid")
    set_accounts
    render :new, status: :unprocessable_entity
  end

  def update
    outflow_account = @transfer.outflow_transaction.entry.account
    return unless require_account_permission!(outflow_account, redirect_path: transactions_url)

    Transfer.transaction do
      update_transfer_status
      update_transfer_details unless transfer_update_params[:status] == "rejected"
    end

    respond_to do |format|
      format.html { redirect_back_or_to transactions_url, notice: t(".success") }
      format.turbo_stream
    end
  end

  def destroy
    outflow_account = @transfer.outflow_transaction.entry.account
    return unless require_account_permission!(outflow_account, redirect_path: transactions_url)

    @transfer.destroy!
    redirect_back_or_to transactions_url, notice: t(".success")
  end

  private
    def set_transfer
      # Finds the transfer and ensures the user has access to it
      accessible_transaction_ids = Current.family.transactions
        .joins(entry: :account)
        .merge(Account.accessible_by(Current.user))
        .select(:id)

      @transfer = Transfer
                    .where(id: params[:id])
                    .where(inflow_transaction_id: accessible_transaction_ids)
                    .first!
    end

    def transfer_params
      params.require(:transfer).permit(:from_account_id, :to_account_id, :amount, :date, :name, :excluded, :exchange_rate, :category_id)
    end

    def set_accounts
      @accounts = accessible_accounts
        .alphabetically
        .includes(
          :account_providers,
          logo_attachment: :blob
        )
    end

    def transfer_update_params
      params.require(:transfer).permit(:notes, :status, :category_id, :name, :amount)
    end

    def update_transfer_status
      if transfer_update_params[:status] == "rejected"
        @transfer.reject!
      elsif transfer_update_params[:status] == "confirmed"
        @transfer.confirm!
      end
    end

    def update_transfer_details
      @transfer.outflow_transaction.update!(category_id: transfer_update_params[:category_id])
      @transfer.update!(notes: transfer_update_params[:notes])

      if transfer_update_params.key?(:name)
        new_name = transfer_update_params[:name].presence
        if new_name
          @transfer.outflow_transaction.entry.update!(name: new_name, user_modified: true)
          @transfer.inflow_transaction.entry.update!(name: new_name, user_modified: true)
        end
      end

      if transfer_update_params[:amount].present? && @transfer.from_account.currency == @transfer.to_account.currency
        new_amount = transfer_update_params[:amount].to_d.abs
        @transfer.outflow_transaction.entry.update!(amount: new_amount, user_modified: true)
        @transfer.inflow_transaction.entry.update!(amount: -new_amount, user_modified: true)
        @transfer.sync_account_later
      end
    end
end
