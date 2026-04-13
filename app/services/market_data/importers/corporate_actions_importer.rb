module MarketData
  module Importers
    # Fetches dividend/split corporate action data from EODHD
    # and inserts into corporate_actions (skips duplicates).
    class CorporateActionsImporter
      def initialize(provider: nil)
        @provider = provider || MarketData::Providers::EodhdClient.new
      end

      def call(symbol:)
        stock = Stock.find_by(symbol: symbol.upcase)
        unless stock
          Rails.logger.warn("[CorporateActionsImporter] Unknown symbol: #{symbol}")
          return 0
        end

        rows = @provider.fetch_corporate_actions(symbol: symbol)
        return 0 if rows.blank?

        inserted = 0
        rows.each do |row|
          ex_date = row[:date] || row["date"]
          next if ex_date.blank?

          CorporateAction.find_or_create_by!(
            stock_id: stock.id,
            action_type: "dividend",
            ex_date: Date.parse(ex_date.to_s)
          ) do |ca|
            ca.value = row[:value] || row["value"]
            ca.description = row[:description] || row["description"] || "Dividend"
          end
          inserted += 1
        rescue ActiveRecord::RecordNotUnique
          # already exists, skip
        end

        Rails.logger.info("[CorporateActionsImporter] #{symbol}: processed #{inserted} corporate actions")
        inserted
      end
    end
  end
end
