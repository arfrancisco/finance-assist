FactoryBot.define do
  factory :feature_snapshot do
    association :stock
    as_of_date { Date.today }
    horizon { "short" }
    feature_version { "v1" }
    momentum_5d { 0.02 }
    momentum_20d { 0.05 }
    momentum_60d { 0.10 }
    volatility_20d { 0.015 }
    avg_volume_20d { 1_000_000 }
    relative_strength { 0.01 }
    valuation_score { 0.5 }
    quality_score { 0.6 }
    liquidity_score { nil }
    catalyst_score { 0.4 }
    risk_score { 0.015 }
    total_score { nil }
  end
end
