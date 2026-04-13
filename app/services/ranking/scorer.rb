module Ranking
  # Applies versioned factor weights to feature snapshots to produce a total score.
  # Stub — implemented in Phase 2.
  #
  # Phase 2 will implement weighted factor scoring per horizon:
  # total_score = Σ (weight_i * normalized_feature_i)
  # Weights are stored in model_versions.weights_json and versioned explicitly.
  class Scorer
    def initialize(model_version:)
      @model_version = model_version
    end

    def call(feature_snapshot:)
      raise NotImplementedError, "Scorer is not yet implemented. See Phase 2."
    end
  end
end
