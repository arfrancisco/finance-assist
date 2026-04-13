module MarketData
  module Importers
    # Fetches the PSE symbol list from EODHD and upserts into the stocks table.
    # Idempotent: runs on any schedule without creating duplicates.
    class SymbolsImporter
      def initialize(provider: nil)
        @provider = provider || MarketData::Providers::EodhdClient.new
      end

      def call
        rows = @provider.fetch_symbols
        return 0 if rows.blank?

        upsert_data = rows.filter_map do |row|
          symbol = row[:Code] || row[:code]
          name = row[:Name] || row[:name]
          next if symbol.blank?

          {
            symbol: symbol.upcase,
            company_name: name,
            is_active: true,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        return 0 if upsert_data.empty?

        result = Stock.upsert_all(
          upsert_data,
          unique_by: :symbol,
          update_only: [ :company_name, :is_active ]
        )

        Rails.logger.info("[SymbolsImporter] Upserted #{result.length} symbols")
        result.length
      end
    end
  end
end
