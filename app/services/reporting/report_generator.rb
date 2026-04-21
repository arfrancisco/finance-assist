module Reporting
  # Generates a research report for a ranked stock prediction using an LLM.
  # Saves the result to prediction_reports (immutable, 1:1 with predictions).
  #
  # Usage:
  #   ReportGenerator.new(prediction).call
  #   ReportGenerator.new(prediction, llm_client: Reporting::Llm::Client.build).call
  class ReportGenerator
    PROMPT_VERSION = "v3-beginner-guidance".freeze

    SYSTEM_PROMPT = <<~PROMPT.strip.freeze
      You are writing a short stock brief for a curious non-expert investor in the Philippines who has little background in stocks or trading.
      Your job is to translate the model's numbers into plain language — and give them a model-based take they can act on with eyes open.

      Writing rules:
      - Use plain, everyday English. Short sentences. Active voice.
      - If you must use a finance term (momentum, volatility, valuation, relative strength, benchmark, drawdown), explain it in plain words in the same sentence it first appears. Example: "volatility (how much the price swings up and down day to day)".
      - Translate numbers into meaning. "Up about 8% over the past month" is better than "momentum_20d = 0.08".
      - Be concrete and specific. Each brief must read differently from others in the same top list — cite at least one concrete number (recent % move or current price) and at least one detail that sets THIS stock apart (a recent filing, a sharp move, the absence of news, sector context, etc.).
      - Do not invent facts. If data is missing (e.g., no valuation or quality score), skip that point silently rather than guessing or flagging the gap as a negative.

      On the "what to do" framing:
      - You MAY share what the data suggests the reader could do (watch, consider a small position, avoid). But:
        - Always label it as the model's view, not personalized advice.
        - Always include at least one honest caveat tied to THIS stock's specific weakness (choppy price, thin data, no fresh news, small-cap liquidity, etc.).
        - Never imply certainty. A 0.85 probability is still a guess — say so.
        - Remind the reader to size small and never bet more than they can afford to lose.

      Respond with exactly these labeled sections (one per line, label followed by content):
      SUMMARY: <1-2 sentences. What has the stock been doing recently (cite a concrete number), and in one phrase what makes this setup different from other top-ranked momentum names today.>
      CATALYSTS: <bullet points of what could push the price up, one per line starting with ->. Ground each in the price action, disclosures, or sector context provided.>
      RISKS: <bullet points of what could go wrong, one per line starting with ->. Translate volatility and risk numbers into plain language.>
      RATIONALE: <1-2 sentences. In plain words, why the model's combined score is high — what mix of recent price trend, steadiness, and company news drove the ranking.>
      GUIDANCE: <1 short paragraph labeled as "the model's view". State the lean (positive / mixed / cautious), a suggested stance (watch / consider a small position / avoid), a time frame tied to the horizon given, and one grain-of-salt caveat specific to THIS stock. End with a reminder that this is the model's view, not advice, and to size small.>
      FOR_BEGINNERS: <1 sentence tied to the horizon. For 5d: short-term momentum picks often reverse quickly — this is a trade, not an investment. For 20d: one month is long enough for news to matter, short enough that price swings still dominate. For 60d: three months lets company fundamentals start to matter, but the model still leans heavily on price trends.>
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
        max_tokens: 900,
        temperature: 0.3
      )

      sections = parse_response(response[:text])

      PredictionReport.create!(
        prediction:     @prediction,
        summary_text:   sections[:summary],
        catalyst_text:  sections[:catalysts],
        risk_text:      sections[:risks],
        rationale_text: sections[:rationale],
        guidance_text:  sections[:guidance],
        education_text: sections[:for_beginners],
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
      lines << "Write the brief for a beginner reader. Follow the section format exactly, including GUIDANCE and FOR_BEGINNERS."
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

    SECTION_LABELS = {
      "SUMMARY"       => :summary,
      "CATALYSTS"     => :catalysts,
      "RISKS"         => :risks,
      "RATIONALE"     => :rationale,
      "GUIDANCE"      => :guidance,
      "FOR_BEGINNERS" => :for_beginners
    }.freeze

    # Parse LLM response into the labeled sections.
    # Falls back to storing the full response in summary if parsing fails.
    def parse_response(text)
      empty = SECTION_LABELS.values.index_with { nil }
      return empty.merge(summary: text) if text.blank?

      sections = empty.dup
      current_key = nil
      buffer = []

      text.each_line do |line|
        stripped = line.strip
        matched_label = SECTION_LABELS.keys.find { |label| stripped.start_with?("#{label}:") }

        if matched_label
          flush_buffer(sections, current_key, buffer)
          current_key = SECTION_LABELS[matched_label]
          buffer = [ stripped.sub(/\A#{matched_label}:\s*/, "") ]
        elsif current_key
          buffer << stripped unless stripped.empty? && buffer.last&.empty?
        end
      end
      flush_buffer(sections, current_key, buffer)

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
