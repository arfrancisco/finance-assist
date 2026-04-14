class IngestFundamentalsJob < ApplicationJob
  queue_as :default

  # Fetches fundamental data (TTM ratios + annual EPS) for all active stocks from EODHD.
  # Triggered weekly (Sundays), or manually via rake task.
  def perform
    Rails.logger.info("[IngestFundamentalsJob] Starting weekly fundamentals ingest")
    importer = MarketData::Importers::FundamentalsImporter.new
    total = 0

    Stock.where(is_active: true).find_each do |stock|
      total += importer.call(symbol: stock.symbol)
      sleep 0.1
    rescue => e
      Rails.logger.error("[IngestFundamentalsJob] Error for #{stock.symbol}: #{e.message}")
    end

    Rails.logger.info("[IngestFundamentalsJob] Done. #{total} fundamental rows upserted.")
  end
end
