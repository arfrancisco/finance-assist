module Validation
  # Aggregates PredictionOutcomes into a weekly SelfAuditRun per horizon.
  # Creates immutable SelfAuditRun records.
  #
  # Metrics computed:
  #   hit_rate          — fraction where beat_benchmark = true
  #   avg_return        — mean raw_return
  #   avg_excess_return — mean excess_return
  #   brier_score       — mean squared error of confidence vs was_positive (0 or 1)
  #   sample_size       — number of outcomes included
  class SelfAudit
    MIN_SAMPLE = 5
    LOOKBACK_DAYS = 90

    def call
      runs_created = 0

      %w[short medium long].each do |horizon|
        outcomes = recent_outcomes(horizon)

        if outcomes.size < MIN_SAMPLE
          Rails.logger.info("[SelfAudit] #{horizon}: only #{outcomes.size} outcomes (need #{MIN_SAMPLE}), skipping")
          next
        end

        metrics = compute_metrics(outcomes)
        run     = build_run(horizon, outcomes.size, metrics)

        SelfAuditRun.create!(
          run_date:          Date.today,
          horizon:           horizon,
          sample_size:       outcomes.size,
          hit_rate:          run[:hit_rate].round(6),
          avg_return:        run[:avg_return].round(6),
          avg_excess_return: run[:avg_excess_return].round(6),
          brier_score:       run[:brier_score].round(6),
          summary_text:      run[:summary_text],
          calibration_notes: run[:calibration_notes]
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

      { hit_rate:, avg_return:, avg_excess_return:, brier_score: }
    end

    def build_run(horizon, sample_size, metrics)
      hit_pct    = (metrics[:hit_rate] * 100).round(1)
      excess_pct = (metrics[:avg_excess_return] * 100).round(2)

      summary = "#{horizon.capitalize}-horizon audit (n=#{sample_size}): " \
                "#{hit_pct}% of predictions beat PSEi benchmark. " \
                "Avg excess return: #{excess_pct}%."

      calibration = if metrics[:brier_score] > 0.25
        "WARNING: Brier score #{metrics[:brier_score].round(4)} > 0.25 — confidence is poorly calibrated. Consider retuning weights."
      else
        "Calibration acceptable (Brier score #{metrics[:brier_score].round(4)})."
      end

      metrics.merge(summary_text: summary, calibration_notes: calibration)
    end
  end
end
