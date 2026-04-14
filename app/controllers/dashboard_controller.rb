class DashboardController < ApplicationController
  def index
    @stock_count        = Stock.count
    @active_stock_count = Stock.where(is_active: true).count
    @price_count        = DailyPrice.count
    @disclosure_count   = Disclosure.count
    @snapshot_count     = FeatureSnapshot.count
    @prediction_count   = Prediction.count
    @report_count       = PredictionReport.count

    @last_eodhd_sync  = RawArtifact.where(source: "eodhd").maximum(:fetched_at)
    @last_pse_edge_sync = Disclosure.maximum(:fetched_at)
    @latest_price_date  = DailyPrice.maximum(:trading_date)
  end
end
