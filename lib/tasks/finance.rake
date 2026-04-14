namespace :finance do
  desc "Refresh the stock universe from EODHD (run weekly)"
  task refresh_symbols: :environment do
    Rails.logger.info("[rake] finance:refresh_symbols starting")
    count = MarketData::Importers::SymbolsImporter.new.call
    puts "Upserted #{count} symbols."
  end

  desc "Fetch latest EOD prices for all active stocks from EODHD (run daily after market close)"
  task ingest_eodhd: :environment do
    date = ENV["DATE"] ? Date.parse(ENV["DATE"]) : nil
    Rails.logger.info("[rake] finance:ingest_eodhd starting (bulk, date=#{date || 'latest'})")
    count = MarketData::Importers::EodPricesImporter.new.call_all(date: date)
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

  desc "Compute feature snapshots for all active stocks (run daily after EODHD ingest)"
  task compute_features: :environment do
    date   = ENV.fetch("DATE", Date.yesterday.to_s)
    symbol = ENV.fetch("SYMBOL", nil)
    as_of  = Date.parse(date)

    stocks = symbol ? Stock.where(symbol: symbol.upcase) : Stock.where(is_active: true)
    Rails.logger.info("[rake] finance:compute_features starting for #{stocks.count} stock(s) as of #{as_of}")

    created = 0
    horizons = %w[5d 20d 60d]

    stocks.find_each do |stock|
      horizons.each do |horizon|
        snapshot = Ranking::FeatureBuilder.new(stock: stock, as_of_date: as_of, horizon: horizon).call
        created += 1 if snapshot
      rescue => e
        Rails.logger.error("[rake] compute_features error for #{stock.symbol}/#{horizon}: #{e.message}")
      end
    end

    puts "Computed #{created} feature snapshots for #{as_of}."
  end

  desc "Score predictions for all feature snapshots on a given date (run daily after compute_features)"
  task score_predictions: :environment do
    date          = ENV.fetch("DATE", Date.yesterday.to_s)
    model_name    = ENV.fetch("MODEL", "v1")
    as_of         = Date.parse(date)

    model_version = ModelVersion.find_by!(version_name: model_name)
    snapshots     = FeatureSnapshot.where(as_of_date: as_of).to_a

    Rails.logger.info("[rake] finance:score_predictions starting: #{snapshots.size} snapshots, model=#{model_name}, date=#{as_of}")

    scorer      = Ranking::Scorer.new(model_version: model_version)
    predictions = scorer.call_batch(feature_snapshots: snapshots)

    puts "Scored #{predictions.compact.size} new predictions for #{as_of} using #{model_name}."

    %w[5d 20d 60d].each do |horizon|
      top = Prediction.for_date(as_of).for_horizon(horizon).top_ranked(10).includes(:stock)
      next if top.empty?
      puts "\nTop 10 #{horizon}-horizon:"
      top.each { |p| puts "  #{p.rank_position}. #{p.stock.symbol} — score: #{p.total_score.round(4)}, #{p.recommendation_type}" }
    end
  end

  desc "Generate LLM research reports for top-ranked predictions (run daily after score_predictions)"
  task generate_reports: :environment do
    date    = ENV.fetch("DATE", Date.yesterday.to_s)
    horizon = ENV.fetch("HORIZON", nil)
    top     = ENV.fetch("TOP", "10").to_i
    as_of   = Date.parse(date)

    horizons = horizon ? [ horizon ] : %w[5d 20d 60d]
    client   = Reporting::Llm::Client.build
    total    = 0

    Rails.logger.info("[rake] finance:generate_reports starting for #{as_of}, horizons=#{horizons.join(',')}, top=#{top}")

    horizons.each do |h|
      predictions = Prediction.for_date(as_of)
                              .for_horizon(h)
                              .top_ranked(top)
                              .includes(:stock, :prediction_report)
                              .select { |p| p.prediction_report.nil? }

      predictions.each do |prediction|
        report = Reporting::ReportGenerator.new(prediction, llm_client: client).call
        Rails.logger.info("[rake] Report generated for #{prediction.stock.symbol}/#{h} | model=#{report.llm_model}")
        total += 1
        sleep 1
      rescue => e
        Rails.logger.error("[rake] generate_reports error for prediction #{prediction.id}: #{e.message}")
      end
    end

    puts "Generated #{total} reports for #{as_of}."
  end

  desc "Evaluate past predictions whose horizon has elapsed (run daily)"
  task evaluate_outcomes: :environment do
    Rails.logger.info("[rake] finance:evaluate_outcomes starting")
    count = Validation::OutcomeEvaluator.new.call
    puts "Evaluated #{count} predictions."
  end

  desc "Retune factor weights from outcome correlations and create a new ModelVersion (run manually)"
  task retune_weights: :environment do
    model_name = ENV.fetch("MODEL", "v1")
    base       = ModelVersion.find_by!(version_name: model_name)

    Rails.logger.info("[rake] finance:retune_weights starting from #{model_name}")
    new_version = Ranking::WeightTuner.new(base_model_version: base).call

    if new_version
      puts "Created new model version: #{new_version.version_name}"
      puts "Run `bin/rails finance:score_predictions MODEL=#{new_version.version_name}` to use it."
    else
      puts "No new version created (insufficient data or no meaningful change)."
    end
  end

  desc "Fetch fundamental data for active stocks from EODHD (run weekly; SYMBOL=ALI for single stock)"
  task ingest_fundamentals: :environment do
    symbol   = ENV.fetch("SYMBOL", nil)
    stocks   = symbol ? Stock.where(symbol: symbol.upcase) : Stock.where(is_active: true)
    importer = MarketData::Importers::FundamentalsImporter.new
    total    = 0

    Rails.logger.info("[rake] finance:ingest_fundamentals starting for #{stocks.count} stock(s)")

    stocks.find_each do |stock|
      count = importer.call(symbol: stock.symbol)
      total += count
      sleep 0.1
    rescue Faraday::ForbiddenError
      puts "Error: EODHD fundamentals endpoint is not available on your current plan. Aborting."
      break
    rescue => e
      Rails.logger.error("[rake] ingest_fundamentals error for #{stock.symbol}: #{e.message}")
    end

    puts "Upserted #{total} fundamental rows."
  end

  desc "Fetch PSEI composite index prices from EODHD (run daily alongside ingest_eodhd)"
  task ingest_pse_index: :environment do
    Rails.logger.info("[rake] finance:ingest_pse_index starting")

    psei_stock = Stock.find_or_create_by!(symbol: "PSEI") do |s|
      s.company_name = "PSE Composite Index"
      s.is_active    = false
    end

    provider = MarketData::Providers::EodhdClient.new
    from = psei_stock.daily_prices.any? ? 5.days.ago.to_date : 2.years.ago.to_date
    rows = provider.fetch_index_data(symbol: "PSEI", from: from, to: Date.today)

    if rows.blank?
      puts "No PSEI index data returned."
      next
    end

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

    Rails.logger.info("[rake] ingest_pse_index: upserted #{result.length} PSEI price rows")
    puts "Upserted #{result.length} PSEI index price rows."
  end

  desc "Generate weekly self-audit summary (run weekly)"
  task self_audit: :environment do
    Rails.logger.info("[rake] finance:self_audit starting")
    count = Validation::SelfAudit.new.call
    puts "Created #{count} self-audit run(s)."
  end
end
