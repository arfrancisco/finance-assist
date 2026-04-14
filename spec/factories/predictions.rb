FactoryBot.define do
  factory :prediction do
    association :stock
    association :model_version
    as_of_date { Date.today }
    horizon { "5d" }
    recommendation_type { "review" }
    rank_position { 1 }
    predicted_probability { 0.65 }
    predicted_direction { "up" }
    expected_return_min { 0.02 }
    expected_return_max { 0.08 }
    confidence { 0.6 }
    total_score { 0.72 }
    benchmark_symbol { "PSEi" }
    feature_version { "v0" }
  end
end
