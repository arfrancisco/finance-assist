class IngestPseIndexJob < ApplicationJob
  queue_as :default

  # Fetches PSEI composite index daily prices from EODHD.
  # Triggered daily alongside IngestEodhdJob.
  # On first run, backfills 2 years of history; subsequent runs fetch the last 5 days.
  def perform
    Rails.logger.info("[IngestPseIndexJob] Starting PSEI index ingest")

    psei_stock = Stock.find_or_create_by!(symbol: "PSEI") do |s|
      s.company_name = "PSE Composite Index"
      s.is_active    = false
    end

    provider = MarketData::Providers::EodhdClient.new
    from = psei_stock.daily_prices.any? ? 5.days.ago.to_date : 2.years.ago.to_date
    rows = provider.fetch_index_data(symbol: "PSEI", from: from, to: Date.today)
    return if rows.blank?

    upsert_data = rows.filter_map do |row|
      date  = row[:date]  || row["date"]
      close = row[:close] || row["close"]
      next if date.blank? || close.nil?

      {
        stock_id:       psei_stock.id,
        trading_date:   Date.parse(date.to_s),
        open:           row[:open]           || row["open"],
        high:           row[:high]           || row["high"],
        low:            row[:low]            || row["low"],
        close:          close,
        adjusted_close: row[:adjusted_close] || row["adjusted_close"],
        volume:         row[:volume]         || row["volume"],
        source:         "eodhd",
        fetched_at:     Time.current,
        created_at:     Time.current,
        updated_at:     Time.current
      }
    end

    result = DailyPrice.upsert_all(
      upsert_data,
      unique_by:   [ :stock_id, :trading_date ],
      update_only: [ :open, :high, :low, :close, :adjusted_close, :volume, :fetched_at ]
    )

    Rails.logger.info("[IngestPseIndexJob] Upserted #{result.length} PSEI price rows.")
  end
end
