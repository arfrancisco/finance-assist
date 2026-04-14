# Seed a placeholder model version so predictions can be created during smoke tests
# and Phase 1 development before real scoring weights are defined in Phase 2.
ModelVersion.find_or_create_by!(version_name: "v0-placeholder") do |mv|
  mv.description = "Placeholder model version for Phase 1 development and smoke testing. No real weights defined."
  mv.algorithm_type = "placeholder"
  mv.weights_json = {}
  mv.notes = "Replace with a real versioned model in Phase 2 when factor scoring is implemented."
end

# Phase 2 model version with real factor weights per horizon.
# Weights are applied to z-score normalized features (clipped to [-3, 3]).
# Negative weights (e.g. volatility_20d) mean higher values lower the score.
ModelVersion.find_or_create_by!(version_name: "v1") do |mv|
  mv.description = "Phase 2 initial factor model. Momentum-tilted for short horizon, quality/value-tilted for long."
  mv.algorithm_type = "weighted_factor"
  mv.weights_json = {
    "5d" => {
      "momentum_5d"      => 0.40,
      "momentum_20d"     => 0.20,
      "volatility_20d"   => -0.20,
      "relative_strength" => 0.10,
      "liquidity_score"  => 0.10
    },
    "20d" => {
      "momentum_20d"     => 0.30,
      "momentum_60d"     => 0.20,
      "relative_strength" => 0.20,
      "valuation_score"  => 0.15,
      "quality_score"    => 0.15
    },
    "60d" => {
      "momentum_60d"     => 0.20,
      "valuation_score"  => 0.25,
      "quality_score"    => 0.25,
      "relative_strength" => 0.20,
      "catalyst_score"   => 0.10
    }
  }
  mv.notes = "Initial Phase 2 weights. Tune in Phase 5 after outcome evaluation data is available."
end

puts "Seeded model_versions: #{ModelVersion.count} record(s)"
