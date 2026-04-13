FactoryBot.define do
  factory :model_version do
    sequence(:version_name) { |n| "v#{n}-test" }
    description { "Test model version" }
    algorithm_type { "weighted_factor" }
    weights_json { { momentum: 0.3, quality: 0.3, valuation: 0.4 } }
  end
end
