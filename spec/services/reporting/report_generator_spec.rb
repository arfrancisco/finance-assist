require "rails_helper"

RSpec.describe Reporting::ReportGenerator do
  let(:stock) { create(:stock, symbol: "ALI", company_name: "Ayala Land Inc") }
  let(:model_version) { create(:model_version) }
  let(:prediction) do
    create(:prediction,
      stock: stock,
      model_version: model_version,
      as_of_date: Date.today,
      horizon: "5d",
      rank_position: 1,
      total_score: 0.72,
      recommendation_type: "buy",
      predicted_direction: "up",
      confidence: 0.75
    )
  end

  let(:llm_response) do
    {
      text: <<~TEXT,
        SUMMARY: ALI shows strong short-term momentum with a high composite score.
        CATALYSTS:
        -> 5-day momentum of 2.5% above recent average
        -> Catalyst score of 0.8 driven by recent disclosures
        RISKS:
        -> Elevated volatility at 1.5%
        -> Liquidity risk if volume drops
        RATIONALE: ALI ranks #1 due to strong momentum and relative outperformance vs PSEi benchmark.
        GUIDANCE: The model's view is cautiously positive — consider a small position over the next week, but keep in mind ALI's daily swings have been choppy and a 0.75 probability is still a guess. Size small.
        FOR_BEGINNERS: Short-term momentum picks often reverse quickly — treat this as a trade, not an investment.
      TEXT
      model: "claude-opus-4-6",
      prompt_version: "v1-llm",
      tokens_in: 350,
      tokens_out: 120
    }
  end

  let(:llm_client) { instance_double(Reporting::Llm::AnthropicClient, complete: llm_response) }

  subject(:generator) { described_class.new(prediction, llm_client: llm_client) }

  describe "#call" do
    it "creates a PredictionReport record" do
      expect { generator.call }.to change(PredictionReport, :count).by(1)
    end

    it "returns the created PredictionReport" do
      expect(generator.call).to be_a(PredictionReport)
    end

    it "sets prompt_version to the current PROMPT_VERSION" do
      expect(generator.call.prompt_version).to eq(Reporting::ReportGenerator::PROMPT_VERSION)
    end

    it "sets llm_model from the LLM response" do
      expect(generator.call.llm_model).to eq("claude-opus-4-6")
    end

    it "calls the LLM client with a system prompt and user prompt" do
      expect(llm_client).to receive(:complete).with(
        hash_including(system: kind_of(String), user: kind_of(String))
      ).and_return(llm_response)
      generator.call
    end

    it "includes the stock symbol in the user prompt" do
      expect(llm_client).to receive(:complete) do |args|
        expect(args[:user]).to include("ALI")
        llm_response
      end
      generator.call
    end

    it "parses SUMMARY into summary_text" do
      report = generator.call
      expect(report.summary_text).to include("strong short-term momentum")
    end

    it "parses CATALYSTS into catalyst_text" do
      report = generator.call
      expect(report.catalyst_text).to include("momentum")
    end

    it "parses RISKS into risk_text" do
      report = generator.call
      expect(report.risk_text).to include("volatility")
    end

    it "parses RATIONALE into rationale_text" do
      report = generator.call
      expect(report.rationale_text).to include("ranks #1")
    end

    it "parses GUIDANCE into guidance_text" do
      report = generator.call
      expect(report.guidance_text).to include("model's view")
      expect(report.guidance_text).to include("small position")
    end

    it "parses FOR_BEGINNERS into education_text" do
      report = generator.call
      expect(report.education_text).to include("momentum")
    end

    it "uses the v3-beginner-guidance prompt version" do
      report = generator.call
      expect(report.prompt_version).to eq("v3-beginner-guidance")
    end

    it "requests max_tokens of 900 from the LLM to fit the new sections" do
      expect(llm_client).to receive(:complete).with(
        hash_including(max_tokens: 900)
      ).and_return(llm_response)
      generator.call
    end

    it "is idempotent — re-running returns the existing report without calling LLM again" do
      first  = generator.call
      expect(llm_client).not_to receive(:complete)
      second = generator.call
      expect(first.id).to eq(second.id)
    end

    context "when LLM response cannot be parsed into sections" do
      let(:llm_response) do
        { text: "This stock looks good.", model: "claude-opus-4-6",
          prompt_version: "v1-llm", tokens_in: 50, tokens_out: 10 }
      end

      it "stores the full response in summary_text as fallback" do
        report = generator.call
        expect(report.summary_text).to eq("This stock looks good.")
      end
    end
  end

  describe "LLM client factory" do
    it "builds an AnthropicClient when LLM_PROVIDER=anthropic" do
      with_env("LLM_PROVIDER" => "anthropic") do
        expect(Reporting::Llm::Client.build).to be_a(Reporting::Llm::AnthropicClient)
      end
    end

    it "builds an OpenaiClient when LLM_PROVIDER=openai" do
      with_env("LLM_PROVIDER" => "openai") do
        expect(Reporting::Llm::Client.build).to be_a(Reporting::Llm::OpenaiClient)
      end
    end

    it "raises for unknown LLM_PROVIDER" do
      with_env("LLM_PROVIDER" => "unknown") do
        expect { Reporting::Llm::Client.build }.to raise_error(ArgumentError)
      end
    end

    def with_env(vars, &block)
      old = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
      vars.each { |k, v| ENV[k] = v }
      block.call
    ensure
      old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end
