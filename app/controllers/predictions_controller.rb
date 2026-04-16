class PredictionsController < ApplicationController
  HORIZONS      = %w[5d 20d 60d].freeze
  DEFAULT_LIMIT = 10

  def index
    @horizon  = HORIZONS.include?(params[:horizon]) ? params[:horizon] : "20d"
    @show_all = params[:show] == "all"
    @symbol   = params[:symbol].presence

    # Default to the latest date we have predictions for
    latest = Prediction.maximum(:as_of_date)
    @date  = params[:date].present? ? Date.parse(params[:date]) : latest
    @dates = Prediction.distinct.order(as_of_date: :desc).pluck(:as_of_date).first(30)

    # Base scope: filter by date + horizon, eager-load associations to avoid
    # N+1 queries when rendering stock names and expandable report panels
    scope = Prediction
              .for_date(@date)
              .for_horizon(@horizon)
              .joins(:stock)
              .includes(:stock, :prediction_report)
              .order(:rank_position)

    # Optional symbol filter — applied before limit so searching in top-10 mode
    # still finds stocks that ranked outside the top 10
    scope = scope.where("stocks.symbol ILIKE ?", "%#{@symbol}%") if @symbol.present?

    # In top-10 mode cap results; in show-all mode return every ranked prediction
    scope = scope.limit(DEFAULT_LIMIT) unless @show_all

    @predictions = scope

    # Total count (unfiltered by symbol) used for the toggle link label
    @total_count = Prediction.for_date(@date).for_horizon(@horizon).count
  end
end
