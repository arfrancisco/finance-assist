FactoryBot.define do
  factory :fundamental do
    association :stock
    period_type { "annual" }
    sequence(:period_end_date) { |n| Date.today - (n * 365) }
    revenue { 10_000_000_000 }
    net_income { 1_000_000_000 }
    eps { 2.50 }
    book_value { 20.0 }
    debt { 5_000_000_000 }
    cash { 2_000_000_000 }
    pe { 12.0 }
    pb { 1.5 }
    dividend_yield { 2.0 }
    roe { 15.0 }
    roa { 5.0 }
  end
end
