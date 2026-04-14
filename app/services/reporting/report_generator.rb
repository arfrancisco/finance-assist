module Reporting
  # Generates a research report for a ranked stock prediction using an LLM.
  # Saves the result to prediction_reports (immutable, 1:1 with predictions).
  #
  # Usage:
  #   ReportGenerator.new(prediction).call
  #   ReportGenerator.new(prediction, llm_client: Reporting::Llm::Client.build).call
  class ReportGenerator
    PROMPT_VERSION = "v1-llm".freeze

    SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      You are a quantitative stock analyst for Philippine Stock Exchange (PSE) equities.
      Write concise, factual research briefs based on quantitative factor data.
      Do not give financial advice. Focus on what the data says and why this stock ranked highly.
      Respond with exactly these labeled sections (one per line, label followed by content):
      SUMMARY: <1-2 sentences>
      CATALYSTS: <bullet points, one per line starting with ->
      RISKS: <bullet points, one per line starting with ->
      RATIONALE: <1-2 sentences explaining the factor score>
    PROMPT

    def initialize(prediction, llm_client: nil)
      @prediction = prediction
      @llm_client = llm_client || Reporting::Llm::Client.build
    end

    # Generates and persists a PredictionReport. Returns the report record.
    # Idempotent — returns existing report if one already exists.
    def call
      return @prediction.prediction_report if @prediction.prediction_report.present?

      stock    = @prediction.stock
      snapshot = FeatureSnapshot.find_by(
        stock_id:   @prediction.stock_id,
        as_of_date: @prediction.as_of_date,
        horizon:    @prediction.horizon
      )

      user_prompt = build_user_prompt(stock, snapshot)
      response    = @llm_client.complete(
        system:     SYSTEM_PROMPT,
        user:       user_prompt,
        max_tokens: 600,
        temperature: 0.3
      )

      sections = parse_response(response[:text])

      PredictionReport.create!(
        prediction:     @prediction,
        summary_text:   sections[:summary],
        catalyst_text:  sections[:catalysts],
        risk_text:      sections[:risks],
        rationale_text: sections[:rationale],
        llm_model:      response[:model],
        prompt_version: PROMPT_VERSION
      )
    end

    private

    def build_user_prompt(stock, snapshot)
      total_ranked = Prediction.for_date(@prediction.as_of_date)
                               .for_horizon(@prediction.horizon)
                               .where.not(rank_position: nil)
                               .count

      disclosures = stock.disclosures
                         .where("disclosure_date >= ?", @prediction.as_of_date - 30)
                         .order(disclosure_date: :desc)
                         .limit(3)
                         .pluck(:title)
                         .compact

      lines = []
      lines << "Stock: #{stock.symbol} — #{stock.company_name}"
      lines << "Horizon: #{@prediction.horizon} | Rank: ##{@prediction.rank_position} of #{total_ranked} | Score: #{fmt(@prediction.total_score)}"
      lines << "Recommendation: #{@prediction.recommendation_type} | Direction: #{@prediction.predicted_direction} | Confidence: #{fmt(@prediction.confidence)}"
      lines << ""
      lines << "Factor Scores:"

      if snapshot
        lines << "  Momentum  5d / 20d / 60d: #{pct(snapshot.momentum_5d)} / #{pct(snapshot.momentum_20d)} / #{pct(snapshot.momentum_60d)}"
        lines << "  Volatility 20d:            #{pct(snapshot.volatility_20d)}"
        lines << "  Relative Strength:         #{fmt(snapshot.relative_strength)}"
        lines << "  Valuation Score:           #{fmt(snapshot.valuation_score)}"
        lines << "  Quality Score (ROE):       #{fmt(snapshot.quality_score)}"
        lines << "  Catalyst Score:            #{fmt(snapshot.catalyst_score)}"
        lines << "  Risk Score:                #{fmt(snapshot.risk_score)}"
      else
        lines << "  (Feature snapshot not available for this prediction)"
      end

      if disclosures.any?
        lines << ""
        lines << "Recent disclosures (last 30 days):"
        disclosures.each { |t| lines << "  - #{t}" }
      end

      lines << ""
      lines << "Write the research brief."
      lines.join("\n")
    end

    # Parse LLM response into the 4 sections.
    # Falls back to storing the full response in summary if parsing fails.
    def parse_response(text)
      return { summary: text, catalysts: nil, risks: nil, rationale: nil } if text.blank?

      sections = { summary: nil, catalysts: nil, risks: nil, rationale: nil }

      current_key = nil
      buffer = []

      text.each_line do |line|
        stripped = line.strip
        if stripped.start_with?("SUMMARY:")
          flush_buffer(sections, current_key, buffer)
          current_key = :summary
          buffer = [ stripped.sub(/\ASUMMARY:\s*/, "") ]
        elsif stripped.start_with?("CATALYSTS:")
          flush_buffer(sections, current_key, buffer)
          current_key = :catalysts
          buffer = [ stripped.sub(/\ACATALYSTS:\s*/, "") ]
        elsif stripped.start_with?("RISKS:")
          flush_buffer(sections, current_key, buffer)
          current_key = :risks
          buffer = [ stripped.sub(/\ARISKS:\s*/, "") ]
        elsif stripped.start_with?("RATIONALE:")
          flush_buffer(sections, current_key, buffer)
          current_key = :rationale
          buffer = [ stripped.sub(/\ARATIONALE:\s*/, "") ]
        elsif current_key
          buffer << stripped unless stripped.empty? && buffer.last&.empty?
        end
      end
      flush_buffer(sections, current_key, buffer)

      # Fallback: if nothing parsed, put everything in summary
      if sections.values.all?(&:nil?)
        sections[:summary] = text.strip
      end

      sections
    end

    def flush_buffer(sections, key, buffer)
      return unless key
      content = buffer.reject(&:empty?).join("\n").strip
      sections[key] = content.presence
    end

    def pct(val)
      return "N/A" unless val
      "#{(val.to_f * 100).round(2)}%"
    end

    def fmt(val)
      return "N/A" unless val
      val.to_f.round(4).to_s
    end
  end
end
