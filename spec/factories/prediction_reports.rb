FactoryBot.define do
  factory :prediction_report do
    association :prediction
    summary_text { "Test summary" }
    catalyst_text { "Test catalyst" }
    risk_text { "Test risk" }
    rationale_text { "Test rationale" }
    llm_model { nil }
    prompt_version { "v0-template" }
  end
end
