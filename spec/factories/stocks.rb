FactoryBot.define do
  factory :stock do
    sequence(:symbol) { |n| "STK#{n}" }
    company_name { "#{symbol} Corporation" }
    sector { "Financials" }
    industry { "Banking" }
    is_active { true }
  end
end
