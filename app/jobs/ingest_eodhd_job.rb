class IngestEodhdJob < ApplicationJob
  queue_as :default

  # Fetches the latest EOD prices for all active stocks.
  # Triggered daily after market close, or manually via rake task.
  def perform(from: Date.today - 5, to: Date.today)
    Rails.logger.info("[IngestEodhdJob] Starting daily EODHD price ingest (#{from} to #{to})")
    importer = MarketData::Importers::EodPricesImporter.new
    count = importer.call_all(from: from.to_date, to: to.to_date)
    Rails.logger.info("[IngestEodhdJob] Done. #{count} price rows upserted.")
  end
end
