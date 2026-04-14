module Ranking
  # Applies versioned factor weights to feature snapshots to produce immutable Predictions.
  #
  # Usage (single):
  #   Scorer.new(model_version:).call(feature_snapshot:)
  #
  # Usage (batch — preferred, enables cross-snapshot normalization):
  #   Scorer.new(model_version:).call_batch(feature_snapshots:)
  #
  # Weights are stored in model_version.weights_json keyed by horizon:
  #   {
  #     "short"  => { "momentum_5d" => 0.4, "volatility_20d" => -0.2, ... },
  #     "medium" => { ... },
  #     "long"   => { ... }
  #   }
  class Scorer
    BENCHMARK_SYMBOL = "PSEI".freeze
    HORIZON_TRADING_DAYS = { "5d" => 5, "20d" => 20, "60d" => 60 }.freeze
    FEATURE_FIELDS = %w[
      momentum_5d momentum_20d momentum_60d volatility_20d avg_volume_20d
      relative_strength valuation_score quality_score liquidity_score
      catalyst_score risk_score
    ].freeze

    def initialize(model_version:)
      @model_version = model_version
      @weights = model_version.weights_json.with_indifferent_access
    end

    # Score a single snapshot. Uses only its own values — no cross-batch normalization.
    def call(feature_snapshot:)
      call_batch(feature_snapshots: [ feature_snapshot ]).first
    end

    # Score a batch of snapshots. Normalizes features across the batch per horizon
    # so cross-stock comparisons are meaningful.
    # Returns an array of Predictions (skips existing ones).
    def call_batch(feature_snapshots:)
      return [] if feature_snapshots.empty?

      # Group by horizon for per-horizon normalization
      by_horizon = feature_snapshots.group_by(&:horizon)

      # Step 1: compute scores in memory — no DB writes yet
      scored = []
      by_horizon.each do |horizon, snapshots|
        horizon_weights = @weights[horizon] || {}
        next if horizon_weights.empty?

        stats = compute_stats(snapshots, horizon_weights.keys)
        snapshots.each do |snapshot|
          row = compute_score(snapshot, horizon_weights, stats)
          scored << row if row
        end
      end

      # Step 2: assign rank_position in memory per horizon before any DB writes
      scored.group_by { |r| r[:horizon] }.each do |_horizon, rows|
        rows.sort_by { |r| -r[:total_score] }.each_with_index do |row, i|
          row[:rank_position] = i + 1
        end
      end

      # Step 3: persist — rank_position is already set so no post-create update needed
      scored.filter_map { |row| persist_prediction(row) }
    end

    private

    # Compute score for a snapshot in memory — no DB writes.
    # Returns a hash of prediction attributes, or nil if already scored.
    def compute_score(snapshot, weights, stats)
      # Skip if already scored for this combination
      return nil if Prediction.exists?(
        stock_id:         snapshot.stock_id,
        as_of_date:       snapshot.as_of_date,
        horizon:          snapshot.horizon,
        model_version_id: @model_version.id
      )

      total = 0.0
      weights.each do |feature, weight|
        raw = snapshot.public_send(feature)&.to_f
        next if raw.nil?

        normalized = normalize(raw, stats[feature])
        total += weight.to_f * normalized
      end

      # Normalize liquidity_score using avg_volume_20d (stored separately)
      liq_weight = weights["liquidity_score"]&.to_f
      if liq_weight
        raw_vol = snapshot.avg_volume_20d&.to_f
        unless raw_vol.nil?
          normalized_liq = normalize(raw_vol, stats["_avg_volume_for_liquidity"])
          total += liq_weight * normalized_liq
        end
      end

      confidence = total.abs.clamp(0.0, 1.0)
      direction  = total >= 0 ? "up" : "down"
      rec_type   = (direction == "up" && confidence > 0.6) ? "buy" : "hold"

      predicted_probability = 1.0 / (1.0 + Math.exp(-total))

      vol = snapshot.volatility_20d&.to_f
      horizon_days = HORIZON_TRADING_DAYS[snapshot.horizon] || 20
      horizon_vol = vol ? (vol * Math.sqrt(horizon_days)).round(6) : nil

      {
        stock_id:               snapshot.stock_id,
        model_version_id:       @model_version.id,
        as_of_date:             snapshot.as_of_date,
        horizon:                snapshot.horizon,
        total_score:            total.round(6),
        confidence:             confidence.round(6),
        predicted_direction:    direction,
        recommendation_type:    rec_type,
        predicted_probability:  predicted_probability.round(6),
        expected_return_min:    horizon_vol ? -horizon_vol : nil,
        expected_return_max:    horizon_vol,
        rank_position:          nil,  # set by call_batch before persisting
        feature_version:        snapshot.feature_version,
        benchmark_symbol:       BENCHMARK_SYMBOL
      }
    end

    def persist_prediction(attrs)
      Prediction.create!(attrs)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("[Scorer] Failed to create prediction for stock_id=#{attrs[:stock_id]}: #{e.message}")
      nil
    end

    # Compute mean + std dev for each weighted feature across the batch.
    # Also computes stats for avg_volume_20d to normalize liquidity_score.
    def compute_stats(snapshots, feature_names)
      stats = {}

      (feature_names + [ "_avg_volume_for_liquidity" ]).each do |key|
        field = key == "_avg_volume_for_liquidity" ? "avg_volume_20d" : key
        values = snapshots.filter_map { |s| s.public_send(field)&.to_f rescue nil }
        next if values.empty?

        mean = values.sum / values.size
        variance = values.sum { |v| (v - mean)**2 } / values.size
        std = Math.sqrt(variance)
        stats[key] = { mean: mean, std: std }
      end

      stats
    end

    # Z-score normalization clipped to [-3, 3]
    def normalize(value, stat)
      return 0.0 if stat.nil? || stat[:std].zero?
      z = (value - stat[:mean]) / stat[:std]
      z.clamp(-3.0, 3.0)
    end

  end
end
