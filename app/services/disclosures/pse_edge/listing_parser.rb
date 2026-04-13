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
        # New PSE EDGE endpoint: /companyDisclosures/search.ax
        # Table rows contain: Date | Company | Template/Type | Title (with openDiscViewer link)
        rows = @doc.css("table tbody tr")
        rows.filter_map { |row| parse_row(row) }
      end

      private

      def parse_row(row)
        cells = row.css("td")
        return nil if cells.size < 2

        # Link contains edge_no as query param: openDiscViewer.do?edge_no=<hex>
        link = row.css("a[href*='openDiscViewer'], a[href*='edge_no']").first
        return nil unless link

        href = link["href"] || ""
        edge_no_match = href.match(/edge_no=([a-f0-9]+)/i)
        source_id = edge_no_match ? edge_no_match[1] : nil
        return nil unless source_id

        {
          source_id: source_id,
          company_name: cells[1]&.text&.strip.presence,
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
