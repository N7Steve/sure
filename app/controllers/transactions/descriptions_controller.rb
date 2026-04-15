class Transactions::DescriptionsController < ApplicationController
  def index
    if params[:account_id].blank? || params[:q].blank?
      render json: []
      return
    end

    @account = Current.family.accounts.find_by(id: params[:account_id])
    
    if @account.nil?
      render json: []
      return
    end

    query = params[:q].to_s.strip

    descriptions = @account.entries
                           .where("name ILIKE ?", "%#{query}%")
                           .where.not(name: query)
                           .distinct
                           .limit(6)
                           .pluck(:name)

    render json: descriptions
  end
end
