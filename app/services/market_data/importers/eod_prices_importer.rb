module MarketData
  module Importers
    # Fetches EOD price data from EODHD and upserts into daily_prices.
    # Supports both single-symbol backfill and all-active-stocks daily updates.
    class EodPricesImporter
      def initialize(provider: nil)
        @provider = provider || MarketData::Providers::EodhdClient.new
      end

      # Import prices for a single symbol over a date range.
      def call(symbol:, from:, to: Date.today)
        stock = Stock.find_by(symbol: symbol.upcase)
        unless stock
          Rails.logger.warn("[EodPricesImporter] Unknown symbol: #{symbol}")
          return 0
        end

        rows = @provider.fetch_eod_prices(symbol: symbol, from: from, to: to)
        return 0 if rows.blank?

        upsert_prices(stock, rows)
      end

      # Import the latest trading day's prices for all active stocks.
      # Uses the bulk endpoint — 1 API call for the entire exchange.
      def call_all(date: nil)
        bulk_rows = @provider.fetch_bulk_eod_prices(date: date)
        return 0 if bulk_rows.blank?

        stock_map = Stock.all.index_by { |s| s.symbol.upcase }
        total = 0

        bulk_rows.group_by { |r| (r[:code] || r["code"]).to_s.split(".").first.upcase }.each do |symbol, rows|
          stock = stock_map[symbol]
          unless stock
            Rails.logger.debug("[EodPricesImporter] No stock record for #{symbol}, skipping")
            next
          end
          # Bulk endpoint returns one row per symbol — wrap in array for upsert_prices
          total += upsert_prices(stock, rows)
        rescue => e
          Rails.logger.error("[EodPricesImporter] Error for #{symbol}: #{e.message}")
        end

        Rails.logger.info("[EodPricesImporter] Total rows upserted: #{total}")
        total
      rescue Faraday::ClientError => e
        Rails.logger.error("[EodPricesImporter] Bulk fetch failed, skipping ingest: #{e.message}")
        0
      end

      private

      def upsert_prices(stock, rows)
        upsert_data = rows.filter_map do |row|
          date = row[:date] || row["date"]
          close = row[:close] || row["close"]
          next if date.blank? || close.nil?

          {
            stock_id: stock.id,
            trading_date: Date.parse(date.to_s),
            open: row[:open] || row["open"],
            high: row[:high] || row["high"],
            low: row[:low] || row["low"],
            close: close,
            adjusted_close: row[:adjusted_close] || row["adjusted_close"],
            volume: row[:volume] || row["volume"],
            source: "eodhd",
            fetched_at: Time.current,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        return 0 if upsert_data.empty?

        result = DailyPrice.upsert_all(
          upsert_data,
          unique_by: [ :stock_id, :trading_date ],
          update_only: [ :open, :high, :low, :close, :adjusted_close, :volume, :fetched_at ]
        )

        Rails.logger.info("[EodPricesImporter] #{stock.symbol}: upserted #{result.length} rows")
        result.length
      end
    end
  end
end
