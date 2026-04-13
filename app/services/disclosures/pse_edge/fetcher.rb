require "digest"

module Disclosures
  module PseEdge
    # Conservative HTTP client for PSE EDGE.
    # Enforces a minimum delay between requests and a per-run request cap
    # to avoid overloading the exchange's servers.
    #
    # Only fetches pages intentionally exposed to users:
    # - Disclosure listing pages
    # - Disclosure detail pages linked from listings
    # - PDF/document attachments linked from detail pages
    #
    # All fetched pages are saved to disk and recorded in raw_artifacts.
    class Fetcher
      BASE_URL = "https://edge.pse.com.ph".freeze
      MIN_DELAY_SECONDS = 2.freeze
      DEFAULT_PER_RUN_CAP = 50.freeze

      def initialize(
        user_agent: ENV.fetch("PSE_EDGE_USER_AGENT", "finance-assist-personal/1.0 (personal research tool)"),
        raw_data_dir: nil,
        per_run_cap: DEFAULT_PER_RUN_CAP
      )
        @user_agent = user_agent
        @raw_data_dir = raw_data_dir || Rails.root.join(ENV.fetch("RAW_DATA_DIR", "data/raw"), "pse_edge")
        @per_run_cap = per_run_cap
        @request_count = 0
        @last_request_at = nil
      end

      # Fetch the disclosure listing page for a given date range (or latest).
      # Returns the raw HTML body.
      def fetch_listing(page: 1, stock_id: nil)
        params = { page: page }
        params[:companyId] = stock_id if stock_id
        url = "#{BASE_URL}/DisclosureSearch/FindDisclosure"
        get(url, params: params, key: "listing/page_#{page}")
      end

      # Fetch a disclosure detail page by its PSE EDGE disclosure ID.
      def fetch_detail(disclosure_id:)
        url = "#{BASE_URL}/DisclosureView/ViewDisclosure/#{disclosure_id}"
        get(url, key: "detail/#{disclosure_id}")
      end

      # Download a PDF or attachment by URL. Returns raw binary body.
      def fetch_attachment(url:, filename:)
        get(url, key: "attachments/#{filename}", binary: true)
      end

      def request_count
        @request_count
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.headers["User-Agent"] = @user_agent
          f.request :retry, max: 1, interval: 5, retry_statuses: [ 503 ]
          f.adapter Faraday.default_adapter
        end
      end

      def get(url, params: {}, key:, binary: false)
        raise_if_cap_exceeded!
        enforce_rate_limit!

        Rails.logger.info("[PseEdgeFetcher] GET #{url} (request ##{@request_count + 1}/#{@per_run_cap})")

        response = connection.get(url) do |req|
          params.each { |k, v| req.params[k] = v }
        end

        @request_count += 1
        @last_request_at = Time.current

        save_artifact(key, response.body, url, binary: binary)

        response.body
      rescue Faraday::Error => e
        Rails.logger.error("[PseEdgeFetcher] Request failed for #{url}: #{e.message}")
        raise
      end

      def enforce_rate_limit!
        return unless @last_request_at

        elapsed = Time.current - @last_request_at
        sleep_for = MIN_DELAY_SECONDS - elapsed
        sleep(sleep_for) if sleep_for > 0
      end

      def raise_if_cap_exceeded!
        if @request_count >= @per_run_cap
          raise "PSE EDGE per-run request cap (#{@per_run_cap}) exceeded. Aborting to avoid overloading the server."
        end
      end

      def save_artifact(key, body, source_url, binary: false)
        dir = @raw_data_dir.join(File.dirname(key))
        FileUtils.mkdir_p(dir)

        ext = binary ? ".pdf" : ".html"
        filename = "#{File.basename(key)}_#{Date.today.strftime('%Y-%m-%d')}#{ext}"
        path = dir.join(filename)

        if binary
          File.binwrite(path, body)
        else
          File.write(path, body)
        end

        checksum = Digest::SHA256.hexdigest(body)
        RawArtifact.create!(
          source: "pse_edge",
          source_url: source_url,
          payload_location: path.to_s,
          checksum: checksum,
          fetched_at: Time.current
        )
      rescue => e
        Rails.logger.warn("[PseEdgeFetcher] Could not save artifact for #{key}: #{e.message}")
      end
    end
  end
end
