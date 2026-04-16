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
                           .limit(20)
                           .pluck(:name)
                           .map(&:strip)
                           .uniq { |name| name.downcase }
                           .first(6)

    render json: descriptions
  end
end
