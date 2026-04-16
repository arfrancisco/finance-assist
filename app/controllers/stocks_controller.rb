class StocksController < ApplicationController
  def index
    # Use correlated subqueries instead of includes to avoid loading all 300k+
    # price rows into Ruby memory just to count them. Each subquery is backed
    # by the (stock_id, trading_date) unique index on daily_prices, making
    # them efficient even as the table grows.
    @stocks = Stock.where(is_active: true)
                   .order(:symbol)
                   .select(
                     "stocks.*",
                     "(SELECT COUNT(*) FROM daily_prices WHERE daily_prices.stock_id = stocks.id) AS price_count",
                     "(SELECT COUNT(*) FROM disclosures  WHERE disclosures.stock_id  = stocks.id) AS disclosure_count",
                     "(SELECT COUNT(*) FROM predictions  WHERE predictions.stock_id  = stocks.id) AS prediction_count",
                     "(SELECT trading_date FROM daily_prices WHERE daily_prices.stock_id = stocks.id ORDER BY trading_date DESC LIMIT 1) AS latest_price_date",
                     "(SELECT close         FROM daily_prices WHERE daily_prices.stock_id = stocks.id ORDER BY trading_date DESC LIMIT 1) AS latest_close"
                   )
  end

  def show
    @stock         = Stock.find(params[:id])
    @latest_prices = @stock.daily_prices.order(trading_date: :desc).limit(10)
    @disclosures   = @stock.disclosures.order(disclosure_date: :desc).limit(10)
    @snapshots     = @stock.feature_snapshots.order(as_of_date: :desc).limit(9)
    @predictions   = @stock.predictions.order(as_of_date: :desc).limit(9)
  end
end
