FactoryBot.define do
  factory :prediction_report do
    association :prediction
    summary_text { "Test summary" }
    catalyst_text { "Test catalyst" }
    risk_text { "Test risk" }
    rationale_text { "Test rationale" }
    guidance_text { "Test guidance" }
    education_text { "Test education" }
    llm_model { nil }
    prompt_version { "v0-template" }
  end
end
