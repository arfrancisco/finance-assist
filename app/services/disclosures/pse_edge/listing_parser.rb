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
        # PSE EDGE /companyDisclosures/search.ax
        # Columns: Template Name (title + company) | Announce Date and Time | PSE Form Number | Report/Circular Number
        # edge_no is in onclick="openPopup('<edge_no>')" on the title link
        @doc.css("table.list tbody tr").filter_map { |row| parse_row(row) }
      end

      private

      def parse_row(row)
        cells = row.css("td")
        return nil if cells.size < 2

        link = cells[0].css("a").first
        return nil unless link

        # edge_no is in onclick attr: openPopup('abc123...')
        onclick = link["onclick"] || ""
        edge_no_match = onclick.match(/openPopup\('([a-f0-9]+)'\)/i)
        source_id = edge_no_match ? edge_no_match[1] : nil
        return nil unless source_id

        # Title text may include "Company Name: Disclosure Title" or just the title
        full_title = link.text.strip
        company_name, title = if full_title.include?(": ")
          full_title.split(": ", 2)
        else
          [ nil, full_title ]
        end

        {
          source_id: source_id,
          company_name: company_name.presence,
          disclosure_type: cells[2]&.text&.strip.presence,
          title: title.presence || full_title,
          disclosure_date: parse_date(cells[1]&.text&.strip),
          detail_url: "https://edge.pse.com.ph/openDiscViewer.do?edge_no=#{source_id}"
        }
      rescue => e
        Rails.logger.warn("[ListingParser] Skipping row due to parse error: #{e.message}")
        nil
      end

      def parse_date(text)
        return nil if text.blank?
        # Format: "Apr 13, 2026 05:22 PM"
        DateTime.strptime(text.strip, "%b %d, %Y %I:%M %p").to_date
      rescue ArgumentError, TypeError
        Date.parse(text) rescue nil
      end

      def build_url(href)
        return href if href.start_with?("http")
        "https://edge.pse.com.ph#{href}"
      end
    end
  end
end
