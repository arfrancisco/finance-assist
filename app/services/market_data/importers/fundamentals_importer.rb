module MarketData
  module Importers
    # Fetches fundamental data from EODHD and upserts into the fundamentals table.
    # Maps EODHD's nested JSON structure to our flat schema.
    class FundamentalsImporter
      def initialize(provider: nil)
        @provider = provider || MarketData::Providers::EodhdClient.new
      end

      def call(symbol:)
        stock = Stock.find_by(symbol: symbol.upcase)
        unless stock
          Rails.logger.warn("[FundamentalsImporter] Unknown symbol: #{symbol}")
          return 0
        end

        data = @provider.fetch_fundamentals(symbol: symbol)
        return 0 if data.blank?

        # Update stock master with any additional fields from fundamentals response
        general = data[:General] || data["General"] || {}
        if general.present?
          stock.update_columns(
            sector: general[:Sector] || general["Sector"] || stock.sector,
            industry: general[:Industry] || general["Industry"] || stock.industry,
            updated_at: Time.current
          )
        end

        # Extract annual earnings if available
        earnings = dig_nested(data, :Earnings, :Annual) || []
        count = 0
        earnings.each do |period|
          period_end = period[:date] || period["date"]
          next if period_end.blank?

          Fundamental.find_or_initialize_by(
            stock_id: stock.id,
            period_type: "annual",
            period_end_date: Date.parse(period_end.to_s)
          ).tap do |f|
            f.eps = period[:epsActual] || period["epsActual"]
            f.source = "eodhd"
            f.fetched_at = Time.current
            f.save!
            count += 1
          end
        rescue => e
          Rails.logger.warn("[FundamentalsImporter] Skipping period #{period_end}: #{e.message}")
        end

        Rails.logger.info("[FundamentalsImporter] #{symbol}: upserted #{count} fundamental rows")
        count
      end

      private

      def dig_nested(hash, *keys)
        keys.reduce(hash) do |h, key|
          h.is_a?(Hash) ? (h[key] || h[key.to_s]) : nil
        end
      end
    end
  end
end
