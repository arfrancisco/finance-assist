module Reporting
  module Llm
    # OpenAI LLM client (alternative to Anthropic).
    # Default model: gpt-4o (override with OPENAI_MODEL env var).
    class OpenaiClient < Client
      API_URL = "https://api.openai.com/v1/chat/completions".freeze
      DEFAULT_MODEL = "gpt-4o".freeze

      def initialize(api_key: ENV["OPENAI_API_KEY"], model: nil)
        @api_key = api_key
        @model = model || ENV.fetch("OPENAI_MODEL", DEFAULT_MODEL)
      end

      def complete(system:, user:, max_tokens: 1024, temperature: 0.3)
        raise "OPENAI_API_KEY is not set" if @api_key.blank?

        body = {
          model: @model,
          max_tokens: max_tokens,
          temperature: temperature,
          messages: [
            { role: "system", content: system },
            { role: "user", content: user }
          ]
        }

        response = connection.post(API_URL) do |req|
          req.headers["Authorization"] = "Bearer #{@api_key}"
          req.headers["content-type"] = "application/json"
          req.body = body.to_json
        end

        parsed = JSON.parse(response.body)
        text = parsed.dig("choices", 0, "message", "content") || ""
        usage = parsed["usage"] || {}
        tokens_in  = usage["prompt_tokens"].to_i
        tokens_out = usage["completion_tokens"].to_i

        log_usage(@model, tokens_in, tokens_out)

        {
          text: text,
          model: @model,
          prompt_version: Client::CURRENT_PROMPT_VERSION,
          tokens_in: tokens_in,
          tokens_out: tokens_out
        }
      rescue Faraday::Error => e
        Rails.logger.error("[OpenaiClient] API error: #{e.message}")
        raise
      end

      private

      def connection
        @connection ||= Faraday.new do |f|
          f.request :retry, max: 2, interval: 1, retry_statuses: [ 429, 503 ]
          f.response :raise_error
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
