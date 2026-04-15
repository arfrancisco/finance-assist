module Types
  class PredictionReportType < Types::BaseObject
    field :id, ID, null: false
    field :summary_text, String, null: true
    field :catalyst_text, String, null: true
    field :risk_text, String, null: true
    field :rationale_text, String, null: true
    field :llm_model, String, null: true
    field :prompt_version, String, null: false
    field :created_at, String, null: false

    def created_at
      object.created_at.iso8601
    end
  end
end
