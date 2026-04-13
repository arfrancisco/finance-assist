module Disclosures
  module PseEdge
    # Parses the HTML of a PSE EDGE disclosure detail page.
    # Extracts body text and attachment URLs (PDFs linked from the page).
    class DetailParser
      def initialize(html)
        @doc = Nokogiri::HTML(html)
      end

      # Returns a hash: { body_text:, attachment_urls: [] }
      def parse
        {
          body_text: extract_body_text,
          attachment_urls: extract_attachment_urls
        }
      end

      private

      def extract_body_text
        # Try common content containers
        content = @doc.css(".disclosure-content, #divDisclosure, .content-area, article, .main-content").first
        content ||= @doc.at("body")
        content&.text&.gsub(/\s+/, " ")&.strip.presence
      end

      def extract_attachment_urls
        @doc.css("a[href$='.pdf'], a[href*='download'], a[href*='attachment']")
          .map { |a| a["href"] }
          .select(&:present?)
          .map { |href| href.start_with?("http") ? href : "https://edge.pse.com.ph#{href}" }
          .uniq
      end
    end
  end
end
