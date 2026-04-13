module Reporting
  # Generates a human-readable research report for a ranked stock prediction.
  # Phase 1: returns templated text built from the Prediction + FeatureSnapshot.
  # Phase 3: replace generate_text_* methods with LLM calls via Reporting::Llm::Client.build.
  #
  # Always saves the result to prediction_reports — provides immutable provenance.
  class ReportGenerator
    PROMPT_VERSION = "v0-template".freeze

    def initialize(prediction, llm_client: nil)
      @prediction = prediction
      @llm_client = llm_client  # nil in Phase 1 (template mode); injected in Phase 3
    end

    # Generates and persists a PredictionReport. Returns the report record.
    def call
      return @prediction.prediction_report if @prediction.prediction_report.present?

      stock    = @prediction.stock
      snapshot = FeatureSnapshot.find_by(
        stock_id: @prediction.stock_id,
        as_of_date: @prediction.as_of_date,
        horizon: @prediction.horizon
      )

      summary  = generate_summary(stock, snapshot)
      catalyst = generate_catalyst(stock, snapshot)
      risk     = generate_risk(stock, snapshot)
      rationale = generate_rationale(snapshot)

      PredictionReport.create!(
        prediction: @prediction,
        summary_text: summary,
        catalyst_text: catalyst,
        risk_text: risk,
        rationale_text: rationale,
        llm_model: nil,  # nil = templated, not LLM-generated
        prompt_version: PROMPT_VERSION
      )
    end

    private

    def generate_summary(stock, snapshot)
      score_str = @prediction.total_score ? format("%.2f", @prediction.total_score) : "N/A"
      rank_str  = @prediction.rank_position ? "##{@prediction.rank_position}" : "unranked"

      "#{stock.symbol} (#{stock.company_name || 'PSE'}) ranks #{rank_str} for " \
      "#{@prediction.horizon}-term review as of #{@prediction.as_of_date}. " \
      "Composite score: #{score_str}. Horizon: #{@prediction.horizon}. " \
      "This is a system-generated template report — LLM narrative will be added in Phase 3."
    end

    def generate_catalyst(stock, snapshot)
      lines = []
      if snapshot
        lines << "5-day momentum: #{pct(snapshot.momentum_5d)}" if snapshot.momentum_5d
        lines << "20-day momentum: #{pct(snapshot.momentum_20d)}" if snapshot.momentum_20d
        lines << "Catalyst score: #{fmt(snapshot.catalyst_score)}" if snapshot.catalyst_score
      end
      recent_disclosures = stock.disclosures.recent.limit(2).pluck(:title).compact
      lines += recent_disclosures.map { |t| "Recent filing: #{t}" } if recent_disclosures.any?

      lines.empty? ? "No catalyst data available yet." : lines.join(" | ")
    end

    def generate_risk(stock, snapshot)
      lines = []
      if snapshot
        lines << "20-day volatility: #{pct(snapshot.volatility_20d)}" if snapshot.volatility_20d
        lines << "Risk score: #{fmt(snapshot.risk_score)}" if snapshot.risk_score
        lines << "Liquidity score: #{fmt(snapshot.liquidity_score)}" if snapshot.liquidity_score
      end
      lines.empty? ? "No risk data available yet." : lines.join(" | ")
    end

    def generate_rationale(snapshot)
      return "Feature snapshot not yet computed for this prediction." unless snapshot

      parts = []
      parts << "Quality: #{fmt(snapshot.quality_score)}" if snapshot.quality_score
      parts << "Valuation: #{fmt(snapshot.valuation_score)}" if snapshot.valuation_score
      parts << "Relative strength: #{fmt(snapshot.relative_strength)}" if snapshot.relative_strength
      parts.empty? ? "Scores not yet populated." : parts.join(" | ")
    end

    def pct(val)
      return "N/A" unless val
      "#{(val * 100).round(2)}%"
    end

    def fmt(val)
      return "N/A" unless val
      val.round(4).to_s
    end
  end
end
