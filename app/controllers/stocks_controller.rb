class StocksController < ApplicationController
  def index
    @stocks = Stock.where(is_active: true)
                   .order(:symbol)
                   .includes(:daily_prices, :disclosures, :predictions)
  end

  def show
    @stock         = Stock.find(params[:id])
    @latest_prices = @stock.daily_prices.order(trading_date: :desc).limit(10)
    @disclosures   = @stock.disclosures.order(disclosure_date: :desc).limit(10)
    @snapshots     = @stock.feature_snapshots.order(as_of_date: :desc).limit(9)
    @predictions   = @stock.predictions.order(as_of_date: :desc).limit(9)
  end
end
