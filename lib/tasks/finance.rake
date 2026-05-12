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

  desc "Backfill historical prices for ALL active stocks over a date range (FROM=2020-01-01 TO=2026-04-16)"
  task backfill_all_prices: :environment do
    from = ENV.fetch("FROM") { abort "Usage: bin/rails finance:backfill_all_prices FROM=2020-01-01 TO=2026-04-16" }
    to   = ENV.fetch("TO", Date.today.to_s)

    from_date = Date.parse(from)
    to_date   = Date.parse(to)

    stocks = Stock.where(is_active: true).where.not(symbol: "PSEI")
    Rails.logger.info("[rake] finance:backfill_all_prices #{from_date}..#{to_date} for #{stocks.count} stocks")
    puts "Backfilling #{stocks.count} stocks from #{from_date} to #{to_date}..."

    importer = MarketData::Importers::EodPricesImporter.new
    total    = 0

    stocks.find_each do |stock|
      count = importer.call(symbol: stock.symbol, from: from_date, to: to_date)
      total += count
      puts "  #{stock.symbol}: #{count} rows"
    rescue => e
      Rails.logger.error("[rake] backfill_all_prices error for #{stock.symbol}: #{e.message}")
      puts "  #{stock.symbol}: ERROR — #{e.message}"
    end

    puts "Done. Total rows upserted: #{total}"
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

  desc "Fetch latest PSE EDGE disclosures (run daily; use PAGES=2 default, or higher for backfill)"
  task ingest_pse_edge: :environment do
    pages = ENV.fetch("PAGES", "2").to_i
    Rails.logger.info("[rake] finance:ingest_pse_edge starting (#{pages} page(s))")
    count = Disclosures::PseEdge::Importer.new(pages: pages).call
    puts "Imported #{count} new disclosures."
  end

  desc "Backfill historical PSE EDGE disclosures — paginates until no rows returned (PAGES=500 default)"
  task backfill_disclosures: :environment do
    pages = ENV.fetch("PAGES", "500").to_i
    Rails.logger.info("[rake] finance:backfill_disclosures starting (up to #{pages} page(s))")
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

  desc "Seed sector and industry from PSE EDGE company directory (idempotent, safe to rerun)"
  task seed_sectors: :environment do
    # Source: https://edge.pse.com.ph/companyDirectory/form.do
    # Format: symbol => [sector, industry]
    SECTOR_DATA = {
      "AAA"    => ["Holding Firms", "Holding Firms"],
      "AB"     => ["Mining and Oil", "Mining"],
      "ABA"    => ["Holding Firms", "Holding Firms"],
      "ABG"    => ["Holding Firms", "Holding Firms"],
      "ABS"    => ["Services", "Media"],
      "ABSP"   => ["Services", "Media"],
      "AC"     => ["Holding Firms", "Holding Firms"],
      "ACE"    => ["Services", "Hotel & Leisure"],
      "ACEN"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "ACR"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "AEV"    => ["Holding Firms", "Holding Firms"],
      "AGI"    => ["Holding Firms", "Holding Firms"],
      "ALCO"   => ["Property", "Property"],
      "ALHI"   => ["Property", "Property"],
      "ALI"    => ["Property", "Property"],
      "ALLDY"  => ["Services", "Retail"],
      "ALLHC"  => ["Property", "Property"],
      "ALTER"  => ["Industrial", "Electricity, Energy, Power & Water"],
      "ANI"    => ["Industrial", "Food, Beverage & Tobacco"],
      "ANS"    => ["Holding Firms", "Holding Firms"],
      "AP"     => ["Industrial", "Electricity, Energy, Power & Water"],
      "APC"    => ["Services", "Other Services"],
      "APL"    => ["Services", "Information Technology"],
      "APO"    => ["Holding Firms", "Holding Firms"],
      "APVI"   => ["Property", "Property"],
      "APX"    => ["Mining and Oil", "Mining"],
      "AR"     => ["Mining and Oil", "Mining"],
      "ARA"    => ["Property", "Property"],
      "AREIT"  => ["Property", "Property"],
      "ASLAG"  => ["Industrial", "Electricity, Energy, Power & Water"],
      "AT"     => ["Mining and Oil", "Mining"],
      "ATN"    => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "AUB"    => ["Financials", "Banks"],
      "AXLM"   => ["Industrial", "Food, Beverage & Tobacco"],
      "BALAI"  => ["Industrial", "Food, Beverage & Tobacco"],
      "BC"     => ["Mining and Oil", "Mining"],
      "BCOR"   => ["Services", "Retail"],
      "BDO"    => ["Financials", "Banks"],
      "BEL"    => ["Services", "Casinos & Gaming"],
      "BH"     => ["Holding Firms", "Holding Firms"],
      "BHI"    => ["Services", "Hotel & Leisure"],
      "BKR"    => ["Financials", "Other Financial Institutions"],
      "BLOOM"  => ["Services", "Casinos & Gaming"],
      "BMM"    => ["Industrial", "Food, Beverage & Tobacco"],
      "BNCOM"  => ["Financials", "Banks"],
      "BPI"    => ["Financials", "Banks"],
      "BRN"    => ["Property", "Property"],
      "BSC"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "C"      => ["Services", "Transportation Services"],
      "CA"     => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "CAT"    => ["Industrial", "Food, Beverage & Tobacco"],
      "CBC"    => ["Financials", "Banks"],
      "CDC"    => ["Property", "Property"],
      "CEB"    => ["Services", "Transportation Services"],
      "CEI"    => ["Property", "Property"],
      "CEU"    => ["Services", "Education"],
      "CHP"    => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "CIC"    => ["Industrial", "Electrical Components & Equipment"],
      "CLI"    => ["Property", "Property"],
      "CNPF"   => ["Industrial", "Food, Beverage & Tobacco"],
      "CNVRG"  => ["Services", "Information Technology"],
      "COAL"   => ["Mining and Oil", "Mining"],
      "COL"    => ["Financials", "Other Financial Institutions"],
      "COSCO"  => ["Holding Firms", "Holding Firms"],
      "CPG"    => ["Property", "Property"],
      "CPM"    => ["Mining and Oil", "Mining"],
      "CREC"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "CREIT"  => ["Property", "Property"],
      "CROWN"  => ["Industrial", "Chemicals"],
      "CSB"    => ["Financials", "Banks"],
      "CTS"    => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "CYBR"   => ["Property", "Property"],
      "DD"     => ["Property", "Property"],
      "DDMPR"  => ["Property", "Property"],
      "DELM"   => ["Industrial", "Food, Beverage & Tobacco"],
      "DFNN"   => ["Services", "Information Technology"],
      "DHI"    => ["Financials", "Other Financial Institutions"],
      "DITO"   => ["Services", "Telecommunications"],
      "DIZ"    => ["Mining and Oil", "Mining"],
      "DMC"    => ["Holding Firms", "Holding Firms"],
      "DMW"    => ["Property", "Property"],
      "DNL"    => ["Industrial", "Food, Beverage & Tobacco"],
      "DWC"    => ["Services", "Hotel & Leisure"],
      "ECP"    => ["Services", "Information Technology"],
      "ECVC"   => ["Mining and Oil", "Mining"],
      "EEI"    => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "EG"     => ["Services", "Casinos & Gaming"],
      "EGRN"   => ["Property", "Property"],
      "ELI"    => ["Property", "Property"],
      "EMI"    => ["Industrial", "Food, Beverage & Tobacco"],
      "ENEX"   => ["Mining and Oil", "Oil"],
      "EURO"   => ["Industrial", "Chemicals"],
      "EW"     => ["Financials", "Banks"],
      "FAF"    => ["Financials", "Other Financial Institutions"],
      "FB"     => ["Industrial", "Food, Beverage & Tobacco"],
      "FCG"    => ["Industrial", "Food, Beverage & Tobacco"],
      "FDC"    => ["Holding Firms", "Holding Firms"],
      "FERRO"  => ["Financials", "Other Financial Institutions"],
      "FEU"    => ["Services", "Education"],
      "FFI"    => ["Financials", "Other Financial Institutions"],
      "FGEN"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "FILRT"  => ["Property", "Property"],
      "FJP"    => ["Holding Firms", "Holding Firms"],
      "FLI"    => ["Property", "Property"],
      "FMETF"  => ["ETF", "ETF-Equity"],
      "FNI"    => ["Mining and Oil", "Mining"],
      "FOOD"   => ["Industrial", "Food, Beverage & Tobacco"],
      "FPH"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "FPI"    => ["Holding Firms", "Holding Firms"],
      "FRUIT"  => ["Industrial", "Food, Beverage & Tobacco"],
      "FYN"    => ["Industrial", "Chemicals"],
      "GEO"    => ["Mining and Oil", "Mining"],
      "GERI"   => ["Property", "Property"],
      "GLO"    => ["Services", "Telecommunications"],
      "GMA7"   => ["Services", "Media"],
      "GMAP"   => ["Services", "Media"],
      "GPH"    => ["Services", "Hotel & Leisure"],
      "GREEN"  => ["Industrial", "Electrical Components & Equipment"],
      "GSMI"   => ["Industrial", "Food, Beverage & Tobacco"],
      "GTCAP"  => ["Holding Firms", "Holding Firms"],
      "HI"     => ["Holding Firms", "Holding Firms"],
      "HOME"   => ["Services", "Retail"],
      "HTI"    => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "I"      => ["Financials", "Other Financial Institutions"],
      "ICT"    => ["Services", "Transportation Services"],
      "IDC"    => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "IMI"    => ["Industrial", "Electrical Components & Equipment"],
      "IMP"    => ["Services", "Information Technology"],
      "INFRA"  => ["Property", "Property"],
      "ION"    => ["Industrial", "Electrical Components & Equipment"],
      "IPM"    => ["Services", "Other Services"],
      "IPO"    => ["Services", "Education"],
      "IS"     => ["Services", "Information Technology"],
      "JAS"    => ["Property", "Property"],
      "JFC"    => ["Industrial", "Food, Beverage & Tobacco"],
      "JGS"    => ["Holding Firms", "Holding Firms"],
      "JOH"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "KEEPR"  => ["Industrial", "Food, Beverage & Tobacco"],
      "KEP"    => ["Property", "Property"],
      "KPPI"   => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "LAND"   => ["Property", "Property"],
      "LBC"    => ["Services", "Transportation Services"],
      "LC"     => ["Mining and Oil", "Mining"],
      "LFM"    => ["Industrial", "Food, Beverage & Tobacco"],
      "LMG"    => ["Financials", "Other Financial Institutions"],
      "LODE"   => ["Holding Firms", "Holding Firms"],
      "LOTO"   => ["Services", "Casinos & Gaming"],
      "LPC"    => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "LPZ"    => ["Holding Firms", "Holding Firms"],
      "LSC"    => ["Services", "Transportation Services"],
      "LTG"    => ["Holding Firms", "Holding Firms"],
      "MA"     => ["Mining and Oil", "Mining"],
      "MAC"    => ["Services", "Transportation Services"],
      "MACAY"  => ["Industrial", "Food, Beverage & Tobacco"],
      "MAH"    => ["Services", "Transportation Services"],
      "MARC"   => ["Mining and Oil", "Mining"],
      "MAXS"   => ["Industrial", "Food, Beverage & Tobacco"],
      "MB"     => ["Services", "Media"],
      "MBC"    => ["Services", "Media"],
      "MBT"    => ["Financials", "Banks"],
      "MED"    => ["Financials", "Other Financial Institutions"],
      "MEDIC"  => ["Services", "Other Services"],
      "MEG"    => ["Property", "Property"],
      "MER"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "MFC"    => ["Financials", "Other Financial Institutions"],
      "MFIN"   => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "MG"     => ["Industrial", "Food, Beverage & Tobacco"],
      "MGH"    => ["Holding Firms", "Holding Firms"],
      "MHC"    => ["Holding Firms", "Holding Firms"],
      "MJC"    => ["Services", "Casinos & Gaming"],
      "MJIC"   => ["Services", "Casinos & Gaming"],
      "MM"     => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "MONDE"  => ["Industrial", "Food, Beverage & Tobacco"],
      "MRC"    => ["Property", "Property"],
      "MREIT"  => ["Property", "Property"],
      "MRSGI"  => ["Services", "Retail"],
      "MVC"    => ["Industrial", "Chemicals"],
      "MWC"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "MWIDE"  => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "MYNLD"  => ["Industrial", "Electricity, Energy, Power & Water"],
      "NI"     => ["Mining and Oil", "Mining"],
      "NIKL"   => ["Mining and Oil", "Mining"],
      "NOW"    => ["Services", "Information Technology"],
      "NRCP"   => ["Financials", "Other Financial Institutions"],
      "NXGEN"  => ["Financials", "Banks"],
      "OGP"    => ["Mining and Oil", "Mining"],
      "OM"     => ["Property", "Property"],
      "OPM"    => ["Mining and Oil", "Oil"],
      "ORE"    => ["Mining and Oil", "Mining"],
      "OV"     => ["Mining and Oil", "Oil"],
      "PA"     => ["Holding Firms", "Holding Firms"],
      "PAL"    => ["Services", "Transportation Services"],
      "PAX"    => ["Services", "Other Services"],
      "PBB"    => ["Financials", "Banks"],
      "PBC"    => ["Financials", "Banks"],
      "PCOR"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "PERC"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "PGOLD"  => ["Services", "Retail"],
      "PHA"    => ["Property", "Property"],
      "PHC"    => ["Services", "Other Services"],
      "PHES"   => ["Property", "Property"],
      "PHN"    => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "PHR"    => ["Services", "Hotel & Leisure"],
      "PIZZA"  => ["Industrial", "Food, Beverage & Tobacco"],
      "PLUS"   => ["Services", "Casinos & Gaming"],
      "PMPC"   => ["Industrial", "Electrical Components & Equipment"],
      "PNB"    => ["Financials", "Banks"],
      "PNC"    => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "PNX"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "PORT"   => ["Services", "Transportation Services"],
      "PPC"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "PRC"    => ["Property", "Property"],
      "PREIT"  => ["Property", "Property"],
      "PRIM"   => ["Holding Firms", "Holding Firms"],
      "PRMX"   => ["Property", "Property"],
      "PSB"    => ["Financials", "Banks"],
      "PSE"    => ["Financials", "Other Financial Institutions"],
      "PTC"    => ["Financials", "Banks"],
      "PTT"    => ["Services", "Telecommunications"],
      "PX"     => ["Mining and Oil", "Mining"],
      "PXP"    => ["Mining and Oil", "Oil"],
      "RCB"    => ["Financials", "Banks"],
      "RCI"    => ["Industrial", "Food, Beverage & Tobacco"],
      "RCR"    => ["Property", "Property"],
      "REDC"   => ["Industrial", "Electricity, Energy, Power & Water"],
      "REG"    => ["Holding Firms", "Holding Firms"],
      "RFM"    => ["Industrial", "Food, Beverage & Tobacco"],
      "RLC"    => ["Property", "Property"],
      "RLT"    => ["Property", "Property"],
      "ROCK"   => ["Property", "Property"],
      "ROX"    => ["Industrial", "Food, Beverage & Tobacco"],
      "RRHI"   => ["Services", "Retail"],
      "SBS"    => ["Services", "Other Services"],
      "SCC"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "SECB"   => ["Financials", "Banks"],
      "SEVN"   => ["Services", "Retail"],
      "SFI"    => ["Industrial", "Food, Beverage & Tobacco"],
      "SGI"    => ["Holding Firms", "Holding Firms"],
      "SGP"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "SHLPH"  => ["Industrial", "Electricity, Energy, Power & Water"],
      "SHNG"   => ["Property", "Property"],
      "SLF"    => ["Financials", "Other Financial Institutions"],
      "SLI"    => ["Property", "Property"],
      "SM"     => ["Holding Firms", "Holding Firms"],
      "SMC"    => ["Holding Firms", "Holding Firms"],
      "SMPH"   => ["Property", "Property"],
      "SOC"    => ["Property", "Property"],
      "SPC"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "SPM"    => ["Holding Firms", "Holding Firms"],
      "SPNEC"  => ["Industrial", "Electricity, Energy, Power & Water"],
      "SRDC"   => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "SSI"    => ["Services", "Retail"],
      "STI"    => ["Services", "Education"],
      "STN"    => ["Industrial", "Other Industrials"],
      "STR"    => ["Property", "Property"],
      "SUN"    => ["Property", "Property"],
      "T"      => ["Industrial", "Construction, Infrastructure & Allied Services"],
      "TBGI"   => ["Services", "Information Technology"],
      "TECH"   => ["Industrial", "Electrical Components & Equipment"],
      "TEL"    => ["Services", "Telecommunications"],
      "TFC"    => ["Property", "Property"],
      "TFHI"   => ["Holding Firms", "Holding Firms"],
      "TOP"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "TUGS"   => ["Services", "Transportation Services"],
      "UBP"    => ["Financials", "Banks"],
      "UNH"    => ["Property", "Property"],
      "UPM"    => ["Mining and Oil", "Mining"],
      "UPSON"  => ["Services", "Retail"],
      "URC"    => ["Industrial", "Food, Beverage & Tobacco"],
      "V"      => ["Financials", "Other Financial Institutions"],
      "VITA"   => ["Industrial", "Food, Beverage & Tobacco"],
      "VLC"    => ["Property", "Property"],
      "VLL"    => ["Property", "Property"],
      "VMC"    => ["Industrial", "Food, Beverage & Tobacco"],
      "VREIT"  => ["Property", "Property"],
      "VVT"    => ["Industrial", "Electricity, Energy, Power & Water"],
      "WEB"    => ["Services", "Casinos & Gaming"],
      "WIN"    => ["Property", "Property"],
      "WLCON"  => ["Services", "Retail"],
      "WPI"    => ["Services", "Hotel & Leisure"],
      "X"      => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "XG"     => ["Small, Medium & Emerging Board", "Small, Medium & Emerging Board"],
      "ZHI"    => ["Holding Firms", "Holding Firms"]
    }.freeze

    updated = 0
    not_found = 0

    SECTOR_DATA.each do |symbol, (sector, industry)|
      rows = Stock.where(symbol: symbol).update_all(sector: sector, industry: industry)
      if rows > 0
        updated += rows
      else
        not_found += 1
        Rails.logger.debug("[seed_sectors] #{symbol}: not found in DB, skipping")
      end
    end

    puts "Sector seed complete: #{updated} stocks updated, #{not_found} symbols not in DB."
    Rails.logger.info("[seed_sectors] Done: #{updated} updated, #{not_found} not found")
  end
end
