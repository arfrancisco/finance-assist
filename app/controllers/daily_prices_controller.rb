class DailyPricesController < ApplicationController
  def index
    @prices = DailyPrice.includes(:stock).order(trading_date: :desc, "stocks.symbol": :asc).joins(:stock)

    @prices = @prices.where("stocks.symbol ILIKE ?", "%#{params[:symbol]}%") if params[:symbol].present?
    @prices = @prices.where("trading_date >= ?", Date.parse(params[:from])) if params[:from].present?
    @prices = @prices.where("trading_date <= ?", Date.parse(params[:to]))   if params[:to].present?

    @prices = @prices.limit(200)
  end
end
