module Types
  class SelfAuditRunType < Types::BaseObject
    field :id, ID, null: false
    field :run_date, String, null: false
    field :horizon, String, null: false
    field :sample_size, Integer, null: true
    field :hit_rate, Float, null: true
    field :avg_return, Float, null: true
    field :avg_excess_return, Float, null: true
    field :brier_score, Float, null: true
    field :calibration_notes, String, null: true
    field :summary_text, String, null: true
    field :created_at, String, null: false

    def run_date
      object.run_date.iso8601
    end

    def created_at
      object.created_at.iso8601
    end
  end
end
