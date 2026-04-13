require "rails_helper"

RSpec.describe Reporting::ReportGenerator do
  let(:stock) { create(:stock, symbol: "ALI", company_name: "Ayala Land Inc") }
  let(:model_version) { create(:model_version) }
  let(:prediction) do
    create(:prediction,
      stock: stock,
      model_version: model_version,
      as_of_date: Date.today,
      horizon: "short",
      rank_position: 1,
      total_score: 0.72
    )
  end

  subject(:generator) { described_class.new(prediction) }

  describe "#call" do
    it "creates a PredictionReport record" do
      expect { generator.call }.to change(PredictionReport, :count).by(1)
    end

    it "returns the created PredictionReport" do
      report = generator.call
      expect(report).to be_a(PredictionReport)
    end

    it "sets the prompt_version to v0-template" do
      report = generator.call
      expect(report.prompt_version).to eq("v0-template")
    end

    it "sets llm_model to nil (templated, not LLM-generated)" do
      report = generator.call
      expect(report.llm_model).to be_nil
    end

    it "includes the stock symbol in the summary" do
      report = generator.call
      expect(report.summary_text).to include("ALI")
    end

    it "includes the horizon in the summary" do
      report = generator.call
      expect(report.summary_text).to include("short")
    end

    it "is idempotent (re-running returns existing report)" do
      first  = generator.call
      second = generator.call
      expect(first.id).to eq(second.id)
    end
  end

  describe "LLM client factory" do
    it "builds an AnthropicClient when LLM_PROVIDER=anthropic" do
      ClimateControl.module_eval {} rescue nil  # no climate_control gem; use env directly
      with_env("LLM_PROVIDER" => "anthropic") { expect(Reporting::Llm::Client.build).to be_a(Reporting::Llm::AnthropicClient) }
    end

    it "builds an OpenaiClient when LLM_PROVIDER=openai" do
      with_env("LLM_PROVIDER" => "openai") { expect(Reporting::Llm::Client.build).to be_a(Reporting::Llm::OpenaiClient) }
    end

    it "raises for unknown LLM_PROVIDER" do
      with_env("LLM_PROVIDER" => "unknown") { expect { Reporting::Llm::Client.build }.to raise_error(ArgumentError) }
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
