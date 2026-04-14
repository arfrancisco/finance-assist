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

        # Extract TTM ratios and most-recent annual financials into a "ttm" row.
        # Note: "ttm" is not in Fundamental::PERIOD_TYPES but no inclusion validator exists.
        # FeatureBuilder#latest_fundamental uses order(period_end_date: :desc).first, so this
        # row (keyed to Date.today) will always be the freshest and provide pe/roe to scoring.
        ttm_attrs = extract_ttm_attrs(data)
        if ttm_attrs.any?
          Fundamental.find_or_initialize_by(
            stock_id:        stock.id,
            period_type:     "ttm",
            period_end_date: Date.today
          ).tap do |f|
            ttm_attrs.each { |attr, val| f.public_send(:"#{attr}=", val) }
            f.source     = "eodhd"
            f.fetched_at = Time.current
            f.save!
            count += 1
          end
        rescue => e
          Rails.logger.warn("[FundamentalsImporter] Skipping TTM row for #{symbol}: #{e.message}")
        end

        Rails.logger.info("[FundamentalsImporter] #{symbol}: upserted #{count} fundamental rows")
        count
      end

      private

      def extract_ttm_attrs(data)
        attrs = {}

        highlights = dig_nested(data, :Highlights) || {}
        attrs[:pe]             = highlights[:PERatio]           || highlights["PERatio"]
        attrs[:pb]             = highlights[:PriceBookMRP]      || highlights["PriceBookMRP"]
        attrs[:roe]            = highlights[:ReturnOnEquityTTM] || highlights["ReturnOnEquityTTM"]
        attrs[:roa]            = highlights[:ReturnOnAssetsTTM] || highlights["ReturnOnAssetsTTM"]
        attrs[:dividend_yield] = highlights[:DividendYield]     || highlights["DividendYield"]

        income_annual = dig_nested(data, :Financials, :Income_Statement, :annual) || {}
        if (recent_income = most_recent_annual(income_annual))
          attrs[:revenue]    = recent_income[:totalRevenue] || recent_income["totalRevenue"]
          attrs[:net_income] = recent_income[:netIncome]    || recent_income["netIncome"]
        end

        balance_annual = dig_nested(data, :Financials, :Balance_Sheet, :annual) || {}
        if (recent_balance = most_recent_annual(balance_annual))
          attrs[:book_value] = recent_balance[:totalStockholderEquity] || recent_balance["totalStockholderEquity"]
          attrs[:debt]       = recent_balance[:longTermDebt]           || recent_balance["longTermDebt"]
          attrs[:cash]       = recent_balance[:cash]                   || recent_balance["cash"]
        end

        attrs.compact
      end

      # Financials sections are hashes keyed by date strings ("2024-12-31" => {...}).
      # Returns the value for the most recent date key.
      def most_recent_annual(annual_hash)
        return nil if annual_hash.blank?
        sorted_key = annual_hash.keys.map(&:to_s).sort.last
        return nil if sorted_key.blank?
        annual_hash[sorted_key.to_sym] || annual_hash[sorted_key]
      end

      def dig_nested(hash, *keys)
        keys.reduce(hash) do |h, key|
          h.is_a?(Hash) ? (h[key] || h[key.to_s]) : nil
        end
      end
    end
  end
end
