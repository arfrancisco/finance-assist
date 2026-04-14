FactoryBot.define do
  factory :prediction_outcome do
    association :prediction
    evaluation_date { Date.today - 5 }
    entry_price { 10.0 }
    exit_price { 10.5 }
    raw_return { 0.05 }
    benchmark_entry { 100.0 }
    benchmark_exit { 101.0 }
    benchmark_return { 0.01 }
    excess_return { 0.04 }
    max_drawdown { -0.005 }
    was_positive { true }
    beat_benchmark { true }
    outcome_label { "win" }
  end
end
