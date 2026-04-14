require "digest"

module MarketData
  module Providers
    # EODHD (EOD Historical Data) API client for PSE market data.
    # Free tier: ~20 API calls per day. All calls are logged to track budget usage.
    # Raw JSON responses are saved to disk and recorded in raw_artifacts for auditability.
    #
    # API docs: https://eodhd.com/financial-apis/
    # PSE exchange code: PSE (symbols formatted as "ALI.PSE")
    class EodhdClient < MarketData::Provider
      BASE_URL = "https://eodhd.com/api".freeze
      PSE_EXCHANGE = "PSE".freeze

      def initialize(api_key: ENV.fetch("EODHD_API_KEY"), raw_data_dir: nil)
        @api_key = api_key
        @raw_data_dir = raw_data_dir || Rails.root.join(ENV.fetch("RAW_DATA_DIR", "data/raw"), "eodhd")
        @call_count = 0
      end

      # Returns array of hashes: [{ symbol:, name:, exchange:, type:, currency: }, ...]
      def fetch_symbols(exchange: PSE_EXCHANGE)
        response = get("exchange-symbol-list/#{exchange}", fmt: "json")
        save_artifact("symbols/#{exchange}", response.body)
        parse_json(response)
      end

      # Returns array of hashes: [{ date:, open:, high:, low:, close:, adjusted_close:, volume: }, ...]
      def fetch_eod_prices(symbol:, from:, to:)
        params = { from: from.to_s, to: to.to_s }
        response = get("eod/#{symbol}.#{PSE_EXCHANGE}", **params)
        save_artifact("eod/#{symbol}", response.body, label: "#{from}_#{to}")
        parse_json(response)
      end

      # Returns array of hashes with dividend/split events
      def fetch_corporate_actions(symbol:)
        response = get("div/#{symbol}.#{PSE_EXCHANGE}", fmt: "json")
        save_artifact("dividends/#{symbol}", response.body)
        parse_json(response)
      end

      # Returns a hash of fundamental data fields
      def fetch_fundamentals(symbol:)
        response = get("fundamentals/#{symbol}.#{PSE_EXCHANGE}")
        save_artifact("fundamentals/#{symbol}", response.body)
        parse_json(response)
      end

      # Returns last trading day's prices for all PSE symbols in one API call.
      # Response is an array of hashes including a `code` field (e.g. "ALI.PSE").
      def fetch_bulk_eod_prices(exchange: PSE_EXCHANGE, date: nil)
        params = date ? { date: date.to_s } : {}
        response = get("eod-bulk-last-day/#{exchange}", **params)
        save_artifact("eod-bulk/#{exchange}", response.body)
        parse_json(response)
      end

      # Fetch index/benchmark OHLCV data (e.g. "PSEI" for the PSE index)
      def fetch_index_data(symbol:, from:, to:)
        params = { from: from.to_s, to: to.to_s }
        response = get("eod/#{symbol}.INDX", **params)
        save_artifact("index/#{symbol}", response.body)
        parse_json(response)
      end

      def call_count
        @call_count
      end

      private

      def connection
        @connection ||= Faraday.new(url: BASE_URL) do |f|
          f.request :retry, max: 2, interval: 1, retry_statuses: [ 429, 503 ]
          f.response :raise_error
          f.adapter Faraday.default_adapter
        end
      end

      def get(path, **params)
        @call_count += 1
        Rails.logger.info("[EODHD] API call ##{@call_count}: GET #{path} #{params}")

        response = connection.get(path) do |req|
          req.params[:api_token] = @api_key
          req.params[:fmt] = "json"
          params.each { |k, v| req.params[k] = v }
        end

        response
      rescue Faraday::ResourceNotFound => e
        Rails.logger.warn("[EODHD] 404 for #{path}: #{e.message}")
        raise
      rescue Faraday::ClientError => e
        Rails.logger.error("[EODHD] Client error for #{path}: #{e.message}")
        raise
      end

      def parse_json(response)
        JSON.parse(response.body, symbolize_names: true)
      end

      def save_artifact(key, body, label: nil)
        timestamp = label || Date.today.strftime("%Y-%m-%d")
        dir = @raw_data_dir.join(key)
        FileUtils.mkdir_p(dir)
        path = dir.join("#{timestamp}.json")
        File.write(path, body)

        checksum = Digest::SHA256.hexdigest(body)
        RawArtifact.create!(
          source: "eodhd",
          source_url: "#{BASE_URL}/#{key}",
          payload_location: path.to_s,
          checksum: checksum,
          fetched_at: Time.current
        )
      rescue => e
        Rails.logger.warn("[EODHD] Could not save artifact for #{key}: #{e.message}")
      end
    end
  end
end
