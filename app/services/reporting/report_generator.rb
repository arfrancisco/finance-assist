module Reporting
  # Generates a research report for a ranked stock prediction using an LLM.
  # Saves the result to prediction_reports (immutable, 1:1 with predictions).
  #
  # Usage:
  #   ReportGenerator.new(prediction).call
  #   ReportGenerator.new(prediction, llm_client: Reporting::Llm::Client.build).call
  class ReportGenerator
    PROMPT_VERSION = "v2-beginner".freeze

    SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      You are writing a short stock brief for a curious non-expert investor in the Philippines who has little background in stocks or trading.
      Your job is to make the numbers understandable, not to impress anyone with jargon.

      Writing rules:
      - Use plain, everyday English. Short sentences. Active voice.
      - If you must use a finance term (momentum, volatility, valuation, relative strength, benchmark, drawdown), explain it in the same sentence in plain words the first time it appears. Example: "volatility (how much the price swings up and down day to day)".
      - Translate numbers into meaning. "Up 8% over the last month" is better than "momentum_20d = 0.08". "Price has been fairly steady" is better than "low volatility".
      - Be concrete and specific. Tie claims back to the data provided (price moves, disclosures, rank).
      - Do not give financial advice. Do not tell the reader to buy, sell, or hold. Describe what the data says, not what the reader should do.
      - Do not invent facts. If data is missing, skip that point rather than guessing.

      Respond with exactly these labeled sections (one per line, label followed by content):
      SUMMARY: <1-2 sentences in plain English: what has the stock been doing recently, and in one phrase why the model flagged it>
      CATALYSTS: <bullet points of what could push the price up, one per line starting with ->. Ground each bullet in the recent price action or disclosures provided.>
      RISKS: <bullet points of what could go wrong, one per line starting with ->. Translate volatility and risk numbers into plain language.>
      RATIONALE: <1-2 sentences explaining, in plain words, why the model's combined score is high — what mix of recent price trend, steadiness, and company news drove the ranking.>
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
                         .pluck(:title, :disclosure_type, :disclosure_date)

      horizon_label = { "5d" => "next ~1 week", "20d" => "next ~1 month", "60d" => "next ~3 months" }[@prediction.horizon] || @prediction.horizon
      percentile    = (total_ranked.to_i > 0 && @prediction.rank_position) ? ((@prediction.rank_position.to_f / total_ranked) * 100).round(1) : nil

      lines = []
      lines << "Stock: #{stock.symbol} — #{stock.company_name}"
      sector_bits = [ stock.sector, stock.industry ].compact.reject(&:empty?)
      lines << "Sector / industry: #{sector_bits.join(' — ')}" if sector_bits.any?
      lines << "Model horizon: #{@prediction.horizon} (covers the #{horizon_label})"
      rank_line = "Rank: ##{@prediction.rank_position} of #{total_ranked}"
      rank_line += " (top #{percentile}%)" if percentile
      lines << rank_line
      lines << "Composite score: #{fmt(@prediction.total_score)} | Direction the model expects: #{@prediction.predicted_direction} | Model confidence: #{fmt(@prediction.confidence)}"
      lines << "Internal recommendation label (do not echo verbatim to the reader): #{@prediction.recommendation_type}"
      lines << ""

      if snapshot
        lines << "Plain-language context (use this phrasing style in your output):"
        lines << "  - Recent price action: #{describe_move(snapshot.momentum_5d, 'past week')}; #{describe_move(snapshot.momentum_20d, 'past month')}; #{describe_move(snapshot.momentum_60d, 'past three months')}."
        lines << "  - Price steadiness: #{describe_volatility(snapshot.volatility_20d)} (volatility over the last 20 trading days)."
        lines << "  - Compared with the broader market: #{describe_relative_strength(snapshot.relative_strength)}."
        lines << ""
        lines << "Raw factor scores (for your reference — translate, do not quote raw numbers):"
        lines << "  Momentum 5d / 20d / 60d (recent price change): #{pct(snapshot.momentum_5d)} / #{pct(snapshot.momentum_20d)} / #{pct(snapshot.momentum_60d)}"
        lines << "  Volatility 20d (how jumpy the price has been): #{pct(snapshot.volatility_20d)}"
        lines << "  Relative strength (vs. overall market): #{fmt(snapshot.relative_strength)}"
        lines << "  Valuation score (cheap vs. expensive signal): #{fmt(snapshot.valuation_score)}"
        lines << "  Quality score (profitability proxy, ROE-based): #{fmt(snapshot.quality_score)}"
        lines << "  Catalyst score (signal from recent company filings): #{fmt(snapshot.catalyst_score)}"
        lines << "  Risk score (combined risk indicator): #{fmt(snapshot.risk_score)}"
      else
        lines << "(Detailed factor data is not available for this prediction — describe what you can from rank and disclosures.)"
      end

      if disclosures.any?
        lines << ""
        lines << "Recent company filings on PSE EDGE (last 30 days):"
        disclosures.each do |title, dtype, ddate|
          bits = [ ddate&.iso8601, dtype, title ].compact.reject { |s| s.to_s.strip.empty? }
          lines << "  - #{bits.join(' · ')}"
        end
      else
        lines << ""
        lines << "Recent company filings: none in the last 30 days."
      end

      lines << ""
      lines << "Write the brief for a beginner reader. Follow the section format exactly."
      lines.join("\n")
    end

    def describe_move(val, window)
      return "no recent price data for the #{window}" unless val
      pct_val = val.to_f * 100
      magnitude = pct_val.abs
      direction = if pct_val > 0.5 then "up"
      elsif pct_val < -0.5 then "down"
      else "roughly flat"
      end
      if direction == "roughly flat"
        "roughly flat over the #{window}"
      else
        descriptor = if magnitude >= 15 then "sharply "
        elsif magnitude >= 5 then ""
        else "modestly "
        end
        "#{descriptor}#{direction} about #{magnitude.round(1)}% over the #{window}"
      end
    end

    def describe_volatility(val)
      return "price-swing data not available" unless val
      v = val.to_f * 100
      if v < 1.5 then "very steady (daily swings are small)"
      elsif v < 3 then "fairly steady"
      elsif v < 5 then "moderately choppy (noticeable daily swings)"
      else "very choppy (large daily swings — price can move several percent in a day)"
      end
    end

    def describe_relative_strength(val)
      return "relative-strength data not available" unless val
      rs = val.to_f
      if rs > 0.05 then "outperforming the overall market recently"
      elsif rs < -0.05 then "underperforming the overall market recently"
      else "tracking roughly in line with the overall market"
      end
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
