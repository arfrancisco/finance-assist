module Reporting
  module Llm
    # Abstract LLM client interface.
    # Concrete implementations: AnthropicClient, OpenaiClient.
    # Select via ENV["LLM_PROVIDER"] ("anthropic" or "openai").
    class Client
      CURRENT_PROMPT_VERSION = "v1-llm".freeze

      # Factory: returns the configured concrete client.
      def self.build
        provider = ENV.fetch("LLM_PROVIDER", "anthropic").downcase
        case provider
        when "anthropic"
          AnthropicClient.new
        when "openai"
          OpenaiClient.new
        else
          raise ArgumentError, "Unknown LLM_PROVIDER: #{provider}. Must be 'anthropic' or 'openai'."
        end
      end

      # Generate a completion.
      # Returns a hash: { text:, model:, prompt_version:, tokens_in:, tokens_out: }
      def complete(system:, user:, max_tokens: 1024, temperature: 0.3)
        raise NotImplementedError, "#{self.class}#complete is not implemented"
      end

      private

      def log_usage(model, tokens_in, tokens_out)
        Rails.logger.info("[LLM] #{self.class.name} | model=#{model} | in=#{tokens_in} out=#{tokens_out}")
      end
    end
  end
end
