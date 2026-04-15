module Disclosures
  module PseEdge
    # Orchestrates the full PSE EDGE disclosure ingestion:
    # 1. Fetch listing page(s)
    # 2. Parse disclosure rows
    # 3. Dedup on source_id; skip already-imported disclosures
    # 4. Fetch detail page for new disclosures
    # 5. Parse body text and attachment URLs
    # 6. Save disclosure record
    # 7. Download attachments for new disclosures
    #
    # Designed to run once daily. Conservative by default (max 2 listing pages).
    class Importer
      DEFAULT_PAGES = 2

      def initialize(fetcher: nil, downloader: nil, pages: DEFAULT_PAGES)
        @fetcher = fetcher || Fetcher.new
        @downloader = downloader || AttachmentDownloader.new(fetcher: @fetcher)
        @pages = pages
      end

      # Idempotent on source_id via exists? guard before create!
      def call
        imported = 0

        total_rows_found = 0

        @pages.times do |i|
          page = i + 1
          html = @fetcher.fetch_listing(page: page)
          rows = ListingParser.new(html).parse
          Rails.logger.info("[PseEdgeImporter] Page #{page}: #{rows.size} disclosure rows found")
          break if rows.empty?

          total_rows_found += rows.size
          rows.each do |row|
            imported += process_row(row)
          end
        end

        if total_rows_found == 0
          Rails.logger.warn("[PseEdgeImporter] No disclosure rows parsed from any listing page. " \
                            "PSE EDGE HTML structure may have changed.")
          return 0
        end

        Rails.logger.info("[PseEdgeImporter] Total new disclosures imported: #{imported}")
        imported
      end

      private

      def process_row(row)
        return 0 if row[:source_id].blank?

        # Dedup: skip if we already have this disclosure
        return 0 if Disclosure.exists?(source_id: row[:source_id])

        # Fetch detail page for body text, attachment URLs, and company name
        detail = fetch_detail(row)

        company_name = row[:company_name].presence || detail[:company_name]
        stock = resolve_stock(company_name)
        return 0 unless stock

        disclosure = Disclosure.create!(
          stock: stock,
          disclosure_type: row[:disclosure_type],
          title: row[:title],
          body_text: detail[:body_text],
          disclosure_date: row[:disclosure_date] || Date.today,
          source_url: row[:detail_url],
          source_id: row[:source_id],
          fetched_at: Time.current
        )

        # Attachment downloading is intentionally skipped — PDFs are large and
        # consume the per-run request cap. Body text from the detail page is sufficient.

        1
      rescue => e
        Rails.logger.error("[PseEdgeImporter] Error processing disclosure #{row[:source_id]}: #{e.message}")
        0
      end

      def fetch_detail(row)
        return { body_text: nil, attachment_urls: [] } if row[:detail_url].blank?

        html = @fetcher.fetch_detail(disclosure_id: row[:source_id])
        DetailParser.new(html).parse
      rescue => e
        Rails.logger.warn("[PseEdgeImporter] Could not fetch detail for #{row[:source_id]}: #{e.message}")
        { body_text: nil, attachment_urls: [] }
      end

      # Strips punctuation and common corporate suffixes so that e.g.
      # "Manila Electric Company" matches "Manila Electric Co" in the DB.
      CORP_SUFFIXES = /\b(corporation|incorporated|company|limited|corp|inc|co|ltd|phils?|philippines?)\b\.?/i

      def normalize_name(name)
        name.downcase
            .gsub(/[^a-z0-9\s]/, "")
            .gsub(CORP_SUFFIXES, "")
            .gsub(/\s+/, " ")
            .strip
      end

      def resolve_stock(company_name)
        return nil if company_name.blank?

        # Try exact match first
        stock = Stock.find_by("LOWER(company_name) = ?", company_name.downcase)
        return stock if stock

        # Normalize and compare against all stocks
        needle = normalize_name(company_name)
        stock = Stock.all.find { |s| normalize_name(s.company_name) == needle }

        unless stock
          Rails.logger.warn("[PseEdgeImporter] Could not match company name to a stock: #{company_name.inspect}")
        end
        stock
      end
    end
  end
end
