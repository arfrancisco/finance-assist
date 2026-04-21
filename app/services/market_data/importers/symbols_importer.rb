require "csv"

module MarketData
  module Importers
    # Fetches the PSE symbol list from EODHD and upserts into the stocks table.
    # After upserting, overlays sector/industry from db/data/pse_sectors.csv,
    # since EODHD's free tier does not include PSE sector classifications.
    # Idempotent: runs on any schedule without creating duplicates.
    class SymbolsImporter
      SECTORS_CSV_PATH = Rails.root.join("db", "data", "pse_sectors.csv")

      def initialize(provider: nil, sectors_csv_path: SECTORS_CSV_PATH)
        @provider = provider || MarketData::Providers::EodhdClient.new
        @sectors_csv_path = sectors_csv_path
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

        overlay_sectors

        result.length
      end

      private

      # Reads db/data/pse_sectors.csv and sets sector/industry per symbol.
      # Rows with a blank sector are skipped so we don't wipe existing values.
      # Missing CSV file is a no-op with a warning (e.g., first deploy before seed).
      def overlay_sectors
        unless File.exist?(@sectors_csv_path)
          Rails.logger.warn("[SymbolsImporter] Sector CSV not found at #{@sectors_csv_path} — skipping overlay")
          return 0
        end

        updated = 0
        CSV.foreach(@sectors_csv_path, headers: true, skip_lines: /\A\s*#/) do |row|
          symbol = row["symbol"]&.strip&.upcase
          sector = row["sector"]&.strip
          industry = row["industry"]&.strip
          next if symbol.blank? || sector.blank?

          attrs = { sector: sector }
          attrs[:industry] = industry if industry.present?
          updated += Stock.where(symbol: symbol).update_all(attrs)
        end

        Rails.logger.info("[SymbolsImporter] Applied sector/industry overlay to #{updated} stocks")
        updated
      end
    end
  end
end
