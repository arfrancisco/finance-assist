class PredictionsController < ApplicationController
  HORIZONS = %w[5d 20d 60d].freeze

  def index
    @horizon = HORIZONS.include?(params[:horizon]) ? params[:horizon] : "20d"

    # Default to the latest date we have predictions for
    latest = Prediction.maximum(:as_of_date)
    @date   = params[:date].present? ? Date.parse(params[:date]) : latest
    @dates  = Prediction.distinct.order(as_of_date: :desc).pluck(:as_of_date).first(30)

    # Top 10 for the selected horizon + date, with stock and report eagerly loaded
    # to avoid N+1 queries on the report expandable panels
    @predictions = Prediction
                     .for_date(@date)
                     .for_horizon(@horizon)
                     .top_ranked(10)
                     .includes(:stock, :prediction_report)
  end
end
