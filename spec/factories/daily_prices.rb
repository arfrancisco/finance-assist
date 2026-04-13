FactoryBot.define do
  factory :daily_price do
    association :stock
    sequence(:trading_date) { |n| Date.today - n }
    open { 10.50 }
    high { 11.00 }
    low { 10.00 }
    close { 10.75 }
    adjusted_close { 10.75 }
    volume { 1_000_000 }
    traded_value { 10_750_000 }
    source { "eodhd" }
    fetched_at { Time.current }
  end
end
