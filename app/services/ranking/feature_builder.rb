module Ranking
  # Computes feature snapshots for a stock as of a given date.
  # Stub — implemented in Phase 2.
  #
  # Phase 2 will compute:
  # - momentum_5d, momentum_20d, momentum_60d
  # - volatility_20d
  # - avg_volume_20d
  # - relative_strength vs PSEi
  # - valuation_score, quality_score, liquidity_score (from fundamentals)
  # - catalyst_score (from recent disclosures)
  # - risk_score
  class FeatureBuilder
    def initialize(stock:, as_of_date:, horizon:)
      @stock = stock
      @as_of_date = as_of_date
      @horizon = horizon
    end

    def call
      raise NotImplementedError, "FeatureBuilder is not yet implemented. See Phase 2."
    end
  end
end
