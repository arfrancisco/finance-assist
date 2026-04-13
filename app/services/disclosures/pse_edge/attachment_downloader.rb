module Disclosures
  module PseEdge
    # Downloads PDF/document attachments from PSE EDGE disclosure pages.
    # Only downloads attachments for newly created disclosure records.
    # Respects the fetcher's rate limit and per-run cap.
    class AttachmentDownloader
      MAX_ATTACHMENTS_PER_DISCLOSURE = 3.freeze

      def initialize(fetcher: nil)
        @fetcher = fetcher || Fetcher.new
      end

      # Downloads attachments for a disclosure and records them as raw artifacts.
      # Returns the number of successfully downloaded attachments.
      def call(disclosure:, attachment_urls:)
        return 0 if attachment_urls.blank?

        urls = attachment_urls.first(MAX_ATTACHMENTS_PER_DISCLOSURE)
        downloaded = 0

        urls.each do |url|
          filename = build_filename(disclosure, url)
          @fetcher.fetch_attachment(url: url, filename: filename)
          downloaded += 1
        rescue => e
          Rails.logger.warn("[AttachmentDownloader] Failed to download #{url}: #{e.message}")
        end

        downloaded
      end

      private

      def build_filename(disclosure, url)
        ext = File.extname(URI.parse(url).path).presence || ".pdf"
        base = "disclosure_#{disclosure.id}_#{disclosure.source_id}"
        "#{base}#{ext}"
      rescue URI::InvalidURIError
        "disclosure_#{disclosure.id}_attachment.pdf"
      end
    end
  end
end
