module Ranking
  # Suggests updated factor weights based on correlation between feature values
  # and prediction outcomes, then creates a new ModelVersion if the weights
  # differ meaningfully from the current version.
  #
  # This is advisory — it creates a new ModelVersion but does NOT automatically
  # switch predictions to use it. Run `finance:score_predictions MODEL=v2` explicitly.
  #
  # Usage:
  #   WeightTuner.new(base_model_version:).call
  class WeightTuner
    MIN_SAMPLES        = 30
    MIN_WEIGHT_CHANGE  = 0.05  # skip new version if no weight changes by more than this
    FEATURE_FIELDS     = %w[
      momentum_5d momentum_20d momentum_60d volatility_20d
      relative_strength valuation_score quality_score catalyst_score
    ].freeze

    def initialize(base_model_version:)
      @base  = base_model_version
    end

    # Returns the new ModelVersion, or nil if insufficient data or no meaningful change.
    def call
      outcomes = load_outcomes
      if outcomes.size < MIN_SAMPLES
        Rails.logger.info("[WeightTuner] Only #{outcomes.size} outcomes (need #{MIN_SAMPLES}). Skipping.")
        return nil
      end

      new_weights = {}

      %w[5d 20d 60d].each do |horizon|
        horizon_outcomes = outcomes.select { |o| o[:horizon] == horizon }
        next if horizon_outcomes.size < MIN_SAMPLES / 3

        correlations = compute_correlations(horizon_outcomes)
        next if correlations.empty?

        normalized = normalize_weights(correlations)
        new_weights[horizon] = normalized
      end

      if new_weights.empty?
        Rails.logger.info("[WeightTuner] No horizons had sufficient data.")
        return nil
      end

      if !meaningful_change?(new_weights)
        Rails.logger.info("[WeightTuner] Suggested weights are too similar to current. No new version created.")
        return nil
      end

      next_version = next_version_name
      model = ModelVersion.create!(
        version_name:   next_version,
        description:    "Auto-tuned from #{outcomes.size} outcomes using feature-return correlations.",
        algorithm_type: "correlation_tuned",
        weights_json:   new_weights,
        notes:          "Based on #{@base.version_name}. Run `finance:score_predictions MODEL=#{next_version}` to use."
      )

      log_weight_diff(new_weights)
      Rails.logger.info("[WeightTuner] Created #{next_version}")
      model
    end

    private

    def load_outcomes
      outcomes = PredictionOutcome.includes(:prediction).to_a

      outcomes.filter_map do |outcome|
        prediction = outcome.prediction
        snapshot   = FeatureSnapshot.find_by(
          stock_id:   prediction.stock_id,
          as_of_date: prediction.as_of_date,
          horizon:    prediction.horizon
        )
        next unless snapshot

        row = { horizon: prediction.horizon, excess_return: outcome.excess_return.to_f }
        FEATURE_FIELDS.each { |f| row[f] = snapshot.public_send(f)&.to_f }
        row
      end
    rescue => e
      Rails.logger.error("[WeightTuner] Error loading outcomes: #{e.message}")
      []
    end

    # Pearson correlation of each feature with excess_return
    def compute_correlations(outcomes)
      returns = outcomes.map { |o| o[:excess_return] }
      return_mean = returns.sum / returns.size.to_f
      return_std  = std_dev(returns)
      return {} if return_std.zero?

      correlations = {}
      FEATURE_FIELDS.each do |feature|
        values = outcomes.map { |o| o[feature] }.compact
        next if values.size < outcomes.size * 0.5  # skip if >50% nil

        feature_mean = values.sum / values.size.to_f
        feature_std  = std_dev(values)
        next if feature_std.zero?

        paired = outcomes.filter_map do |o|
          next if o[feature].nil?
          [ o[feature] - feature_mean, o[:excess_return] - return_mean ]
        end

        cov = paired.sum { |fv, rv| fv * rv } / paired.size.to_f
        corr = cov / (feature_std * return_std)
        correlations[feature] = corr.clamp(-1.0, 1.0)
      end

      correlations
    end

    # Normalize correlations so absolute values sum to 1.0, preserving sign
    def normalize_weights(correlations)
      total = correlations.values.sum(&:abs)
      return {} if total.zero?

      correlations.transform_values { |v| (v / total).round(4) }
    end

    def meaningful_change?(new_weights)
      new_weights.any? do |horizon, weights|
        current = @base.weights_json[horizon] || {}
        weights.any? do |feature, new_w|
          old_w = current[feature]&.to_f || 0.0
          (new_w - old_w).abs >= MIN_WEIGHT_CHANGE
        end
      end
    end

    def next_version_name
      existing = ModelVersion.pluck(:version_name)
                              .filter_map { |n| n.match(/\Av(\d+)\z/)&.[](1)&.to_i }
      next_num = (existing.max || 1) + 1
      "v#{next_num}"
    end

    def log_weight_diff(new_weights)
      new_weights.each do |horizon, weights|
        current = @base.weights_json[horizon] || {}
        Rails.logger.info("[WeightTuner] #{horizon} weight changes:")
        weights.each do |feature, new_w|
          old_w = current[feature]&.to_f || 0.0
          diff  = new_w - old_w
          Rails.logger.info("  #{feature}: #{old_w.round(4)} → #{new_w.round(4)} (#{diff >= 0 ? '+' : ''}#{diff.round(4)})")
        end
      end
    end

    def std_dev(values)
      return 0.0 if values.size < 2
      mean = values.sum / values.size.to_f
      variance = values.sum { |v| (v - mean)**2 } / values.size.to_f
      Math.sqrt(variance)
    end
  end
end
