class DashboardController < ApplicationController
  def index
    # Counts are cached for 5 minutes — they don't need to be real-time and
    # full-table COUNTs on large tables (e.g. daily_prices at 300k+ rows) are
    # expensive to run on every page load.
    @stock_count        = Rails.cache.fetch("dashboard/stock_count",        expires_in: 5.minutes) { Stock.count }
    @active_stock_count = Rails.cache.fetch("dashboard/active_stock_count", expires_in: 5.minutes) { Stock.where(is_active: true).count }
    @price_count        = Rails.cache.fetch("dashboard/price_count",        expires_in: 5.minutes) { DailyPrice.count }
    @disclosure_count   = Rails.cache.fetch("dashboard/disclosure_count",   expires_in: 5.minutes) { Disclosure.count }
    @snapshot_count     = Rails.cache.fetch("dashboard/snapshot_count",     expires_in: 5.minutes) { FeatureSnapshot.count }
    @prediction_count   = Rails.cache.fetch("dashboard/prediction_count",   expires_in: 5.minutes) { Prediction.count }
    @report_count       = Rails.cache.fetch("dashboard/report_count",       expires_in: 5.minutes) { PredictionReport.count }

    # Freshness indicators are intentionally left uncached — they're fast
    # indexed MAX() lookups and stale sync timestamps would be misleading.
    @last_eodhd_sync    = RawArtifact.where(source: "eodhd").maximum(:fetched_at)
    @last_pse_edge_sync = Disclosure.maximum(:fetched_at)
    @latest_price_date  = DailyPrice.maximum(:trading_date)
  end
end
