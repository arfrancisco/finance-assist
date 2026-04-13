module Reporting
  module Llm
    # Anthropic (Claude) LLM client.
    # Uses prompt caching on the system block to reduce token costs on repeated calls.
    # Default model: claude-opus-4-6 (override with ANTHROPIC_MODEL env var).
    class AnthropicClient < Client
      API_URL = "https://api.anthropic.com/v1/messages".freeze
      API_VERSION = "2023-06-01".freeze
      DEFAULT_MODEL = "claude-opus-4-6".freeze

      def initialize(api_key: ENV["ANTHROPIC_API_KEY"], model: nil)
        @api_key = api_key
        @model = model || ENV.fetch("ANTHROPIC_MODEL", DEFAULT_MODEL)
      end

      def complete(system:, user:, max_tokens: 1024, temperature: 0.3)
        raise "ANTHROPIC_API_KEY is not set" if @api_key.blank?

        body = {
          model: @model,
          max_tokens: max_tokens,
          temperature: temperature,
          system: [
            {
              type: "text",
              text: system,
              cache_control: { type: "ephemeral" }  # prompt caching on system block
            }
          ],
          messages: [
            { role: "user", content: user }
          ]
        }

        response = connection.post(API_URL) do |req|
          req.headers["x-api-key"] = @api_key
          req.headers["anthropic-version"] = API_VERSION
          req.headers["anthropic-beta"] = "prompt-caching-2024-07-31"
          req.headers["content-type"] = "application/json"
          req.body = body.to_json
        end

        parsed = JSON.parse(response.body)
        text = parsed.dig("content", 0, "text") || ""
        usage = parsed["usage"] || {}
        tokens_in  = usage["input_tokens"].to_i
        tokens_out = usage["output_tokens"].to_i

        log_usage(@model, tokens_in, tokens_out)

        {
          text: text,
          model: @model,
          prompt_version: Client::CURRENT_PROMPT_VERSION,
          tokens_in: tokens_in,
          tokens_out: tokens_out
        }
      rescue Faraday::Error => e
        Rails.logger.error("[AnthropicClient] API error: #{e.message}")
        raise
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.request :retry, max: 2, interval: 1, retry_statuses: [ 529 ]
          f.response :raise_error
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
