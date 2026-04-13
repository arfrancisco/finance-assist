module Disclosures
  module PseEdge
    # Parses the HTML of a PSE EDGE disclosure listing page.
    # Extracts rows of disclosure summaries: company, type, title, date, detail URL, source_id.
    #
    # Resilient to layout changes — returns empty array rather than raising on parse errors.
    class ListingParser
      def initialize(html)
        @doc = Nokogiri::HTML(html)
      end

      # Returns an array of hashes:
      # [{ source_id:, company_name:, disclosure_type:, title:, disclosure_date:, detail_url: }, ...]
      def parse
        rows = @doc.css("table#tblResults tbody tr, table.disclosure-table tbody tr, .disclosure-row")

        if rows.empty?
          # Fallback: look for any table rows with disclosure-like content
          rows = @doc.css("tbody tr")
        end

        rows.filter_map { |row| parse_row(row) }
      end

      private

      def parse_row(row)
        cells = row.css("td")
        return nil if cells.empty?

        # PSE EDGE listing typically has: Date | Company | Type | Title | link
        # Exact selectors depend on live HTML — this covers the common structure
        link = row.css("a[href*='DisclosureView'], a[href*='ViewDisclosure']").first
        return nil unless link

        href = link["href"] || ""
        id_match = href.match(/\/(\d+)(?:\/|\z)/)
        source_id = id_match ? id_match[1] : href.split("/").last

        {
          source_id: source_id.presence,
          company_name: cells[1]&.text&.strip.presence || link.text.strip,
          disclosure_type: cells[2]&.text&.strip.presence,
          title: (cells[3]&.text || link.text).strip.presence,
          disclosure_date: parse_date(cells[0]&.text&.strip),
          detail_url: build_url(href)
        }
      rescue => e
        Rails.logger.warn("[ListingParser] Skipping row due to parse error: #{e.message}")
        nil
      end

      def parse_date(text)
        return nil if text.blank?
        Date.parse(text)
      rescue ArgumentError, TypeError
        nil
      end

      def build_url(href)
        return href if href.start_with?("http")
        "https://edge.pse.com.ph#{href}"
      end
    end
  end
end
