namespace :finance do
  desc "Refresh the stock universe from EODHD (run weekly)"
  task refresh_symbols: :environment do
    Rails.logger.info("[rake] finance:refresh_symbols starting")
    count = MarketData::Importers::SymbolsImporter.new.call
    puts "Upserted #{count} symbols."
  end

  desc "Fetch latest EOD prices for all active stocks from EODHD (run daily after market close)"
  task ingest_eodhd: :environment do
    from = ENV.fetch("FROM", (Date.today - 5).to_s)
    to   = ENV.fetch("TO",   Date.today.to_s)
    Rails.logger.info("[rake] finance:ingest_eodhd starting (#{from} to #{to})")
    count = MarketData::Importers::EodPricesImporter.new.call_all(
      from: Date.parse(from),
      to:   Date.parse(to)
    )
    puts "Upserted #{count} price rows."
  end

  desc "Backfill historical prices for a single symbol (SYMBOL=ALI FROM=2020-01-01 TO=2024-12-31)"
  task backfill_prices: :environment do
    symbol = ENV.fetch("SYMBOL") { abort "Usage: bin/rails finance:backfill_prices SYMBOL=ALI FROM=2020-01-01 TO=2024-12-31" }
    from   = ENV.fetch("FROM")   { abort "FROM date is required" }
    to     = ENV.fetch("TO",     Date.today.to_s)

    Rails.logger.info("[rake] finance:backfill_prices #{symbol} #{from}..#{to}")
    count = MarketData::Importers::EodPricesImporter.new.call(
      symbol: symbol,
      from:   Date.parse(from),
      to:     Date.parse(to)
    )
    puts "Upserted #{count} price rows for #{symbol}."
  end

  desc "Fetch latest PSE EDGE disclosures (run daily)"
  task ingest_pse_edge: :environment do
    pages = ENV.fetch("PAGES", "2").to_i
    Rails.logger.info("[rake] finance:ingest_pse_edge starting (#{pages} page(s))")
    count = Disclosures::PseEdge::Importer.new(pages: pages).call
    puts "Imported #{count} new disclosures."
  end

  desc "Evaluate past predictions whose horizon has elapsed (Phase 4)"
  task evaluate_outcomes: :environment do
    puts "Outcome evaluation not yet implemented — coming in Phase 4."
    # TODO Phase 4: Validation::OutcomeEvaluator.new.call
  end

  desc "Generate weekly self-audit summary (Phase 4)"
  task self_audit: :environment do
    puts "Self-audit not yet implemented — coming in Phase 4."
    # TODO Phase 4: Validation::SelfAudit.new.call
  end
end
