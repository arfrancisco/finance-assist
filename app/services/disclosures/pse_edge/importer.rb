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
      DEFAULT_PAGES = 2.freeze

      def initialize(fetcher: nil, downloader: nil, pages: DEFAULT_PAGES)
        @fetcher = fetcher || Fetcher.new
        @downloader = downloader || AttachmentDownloader.new(fetcher: @fetcher)
        @pages = pages
      end

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
          raise "[PseEdgeImporter] No disclosure rows parsed from any listing page. " \
                "PSE EDGE HTML structure may have changed."
        end

        Rails.logger.info("[PseEdgeImporter] Total new disclosures imported: #{imported}")
        imported
      end

      private

      def process_row(row)
        return 0 if row[:source_id].blank?

        # Dedup: skip if we already have this disclosure
        return 0 if Disclosure.exists?(source_id: row[:source_id])

        stock = resolve_stock(row[:company_name])
        return 0 unless stock

        # Fetch detail page for body text and attachment URLs
        detail = fetch_detail(row)

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

        # Download attachments only for new disclosures
        if detail[:attachment_urls].any?
          @downloader.call(disclosure: disclosure, attachment_urls: detail[:attachment_urls])
        end

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

      def resolve_stock(company_name)
        return nil if company_name.blank?

        # Try exact company name match first, then partial
        Stock.find_by("LOWER(company_name) = ?", company_name.downcase) ||
          Stock.where("LOWER(company_name) LIKE ?", "%#{company_name.downcase.split.first}%").first
      end
    end
  end
end
