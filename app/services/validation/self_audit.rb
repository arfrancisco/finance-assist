module Validation
  # Aggregates PredictionOutcomes into a weekly SelfAuditRun per horizon.
  # Creates immutable SelfAuditRun records.
  #
  # Core metrics (columns):
  #   hit_rate          — fraction where beat_benchmark = true
  #   avg_return        — mean raw_return
  #   avg_excess_return — mean excess_return
  #   brier_score       — mean squared error of confidence vs was_positive (0 or 1)
  #   sample_size       — number of outcomes included
  #
  # Extended metrics (metrics_json):
  #   precision         — of "buy" predictions, fraction that beat benchmark
  #   recall            — of actual wins, fraction predicted as "buy"
  #   f1                — harmonic mean of precision and recall
  #   top3_avg_return   — mean raw_return of rank_position 1–3
  #   top5_avg_return   — mean raw_return of rank_position 1–5
  #   rank_spread       — top-quartile avg return minus bottom-quartile avg return
  #   calibration_bands — hit rate per confidence bucket [0–0.25), [0.25–0.5), [0.5–0.75), [0.75–1.0)
  class SelfAudit
    MIN_SAMPLE = 5
    LOOKBACK_DAYS = 90

    # Idempotent on (run_date, horizon) via upsert
    def call
      runs_created = 0

      %w[5d 20d 60d].each do |horizon|
        outcomes = recent_outcomes(horizon)

        if outcomes.size < MIN_SAMPLE
          Rails.logger.info("[SelfAudit] #{horizon}: only #{outcomes.size} outcomes (need #{MIN_SAMPLE}), skipping")
          next
        end

        metrics = compute_metrics(outcomes)
        run     = build_run(horizon, outcomes.size, metrics)

        # Idempotent on (run_date, horizon) via upsert
        SelfAuditRun.upsert(
          {
            run_date:          Date.today,
            horizon:           horizon,
            sample_size:       outcomes.size,
            hit_rate:          run[:hit_rate].round(6),
            avg_return:        run[:avg_return].round(6),
            avg_excess_return: run[:avg_excess_return].round(6),
            brier_score:       run[:brier_score].round(6),
            summary_text:      run[:summary_text],
            calibration_notes: run[:calibration_notes],
            metrics_json:      run[:metrics_json]
          },
          unique_by: [ :run_date, :horizon ],
          update_only: %i[
            sample_size hit_rate avg_return avg_excess_return brier_score
            summary_text calibration_notes metrics_json
          ]
        )

        runs_created += 1
        Rails.logger.info("[SelfAudit] #{horizon}: hit_rate=#{(run[:hit_rate] * 100).round(1)}% avg_excess=#{(run[:avg_excess_return] * 100).round(2)}% brier=#{run[:brier_score].round(4)} n=#{outcomes.size}")
      rescue => e
        Rails.logger.error("[SelfAudit] Error for #{horizon}: #{e.message}")
      end

      Rails.logger.info("[SelfAudit] Created #{runs_created} audit runs")
      runs_created
    end

    private

    def recent_outcomes(horizon)
      PredictionOutcome
        .joins(:prediction)
        .where(predictions: { horizon: horizon })
        .where("prediction_outcomes.evaluation_date >= ?", Date.today - LOOKBACK_DAYS)
        .includes(:prediction)
        .to_a
    end

    def compute_metrics(outcomes)
      n = outcomes.size.to_f

      hit_rate          = outcomes.count(&:beat_benchmark) / n
      avg_return        = outcomes.sum { |o| o.raw_return.to_f } / n
      avg_excess_return = outcomes.sum { |o| o.excess_return.to_f } / n

      # Brier score: mean((confidence - actual)^2) where actual = 1 if was_positive else 0
      brier_score = outcomes.sum do |o|
        actual = o.was_positive ? 1.0 : 0.0
        conf   = o.prediction.confidence&.to_f || 0.5
        (conf - actual)**2
      end / n

      {
        hit_rate:,
        avg_return:,
        avg_excess_return:,
        brier_score:,
        extended: compute_extended_metrics(outcomes)
      }
    end

    def compute_extended_metrics(outcomes)
      buys     = outcomes.select { |o| o.prediction.recommendation_type == "buy" }
      wins     = outcomes.select(&:beat_benchmark)

      true_positives = buys.count(&:beat_benchmark).to_f

      precision = buys.any? ? (true_positives / buys.size).round(6) : nil
      recall    = wins.any? ? (true_positives / wins.size).round(6) : nil
      f1        = (precision && recall && (precision + recall) > 0) ?
                    ((2.0 * precision * recall) / (precision + recall)).round(6) : nil

      top3 = ranked_avg_return(outcomes, 3)
      top5 = ranked_avg_return(outcomes, 5)

      rank_spread = compute_rank_spread(outcomes)

      calibration_bands = compute_calibration_bands(outcomes)

      {
        precision:,
        recall:,
        f1:,
        top3_avg_return: top3,
        top5_avg_return: top5,
        rank_spread:,
        calibration_bands:
      }
    end

    # Average raw_return for the top-N predictions by rank_position
    def ranked_avg_return(outcomes, n)
      top = outcomes
              .select { |o| o.prediction.rank_position&.<= n }
              .sort_by { |o| o.prediction.rank_position }
      return nil if top.empty?
      (top.sum { |o| o.raw_return.to_f } / top.size).round(6)
    end

    # Top-quartile avg return minus bottom-quartile avg return
    def compute_rank_spread(outcomes)
      ranked = outcomes.select { |o| o.prediction.rank_position }
                       .sort_by { |o| o.prediction.rank_position }
      return nil if ranked.size < 4

      q_size     = (ranked.size / 4.0).ceil
      top_q      = ranked.first(q_size)
      bottom_q   = ranked.last(q_size)

      top_avg    = top_q.sum { |o| o.raw_return.to_f } / top_q.size
      bottom_avg = bottom_q.sum { |o| o.raw_return.to_f } / bottom_q.size
      (top_avg - bottom_avg).round(6)
    end

    # Hit rate per confidence band: { "0.00-0.25" => { n:, hit_rate: }, ... }
    def compute_calibration_bands(outcomes)
      bands = {
        "0.00-0.25" => [],
        "0.25-0.50" => [],
        "0.50-0.75" => [],
        "0.75-1.00" => []
      }

      outcomes.each do |o|
        conf = o.prediction.confidence&.to_f || 0.0
        key = case conf
              when 0.0...0.25 then "0.00-0.25"
              when 0.25...0.50 then "0.25-0.50"
              when 0.50...0.75 then "0.50-0.75"
              else "0.75-1.00"
              end
        bands[key] << o
      end

      bands.transform_values do |group|
        next nil if group.empty?
        { n: group.size, hit_rate: (group.count(&:beat_benchmark).to_f / group.size).round(6) }
      end
    end

    def build_run(horizon, sample_size, metrics)
      hit_pct    = (metrics[:hit_rate] * 100).round(1)
      excess_pct = (metrics[:avg_excess_return] * 100).round(2)
      ext        = metrics[:extended]

      summary = "#{horizon.capitalize}-horizon audit (n=#{sample_size}): " \
                "#{hit_pct}% of predictions beat PSEi benchmark. " \
                "Avg excess return: #{excess_pct}%."

      if ext[:f1]
        summary += " Buy precision=#{(ext[:precision] * 100).round(1)}% recall=#{(ext[:recall] * 100).round(1)}% F1=#{ext[:f1].round(3)}."
      end

      calibration = if metrics[:brier_score] > 0.25
        "WARNING: Brier score #{metrics[:brier_score].round(4)} > 0.25 — confidence is poorly calibrated. Consider retuning weights."
      else
        "Calibration acceptable (Brier score #{metrics[:brier_score].round(4)})."
      end

      metrics.merge(
        summary_text:      summary,
        calibration_notes: calibration,
        metrics_json:      ext
      )
    end
  end
end
