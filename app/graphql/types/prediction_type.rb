module Types
  class PredictionType < Types::BaseObject
    field :id, ID, null: false
    field :as_of_date, String, null: false
    field :horizon, String, null: false
    field :rank_position, Integer, null: true
    field :total_score, Float, null: false
    field :predicted_probability, Float, null: true
    field :predicted_direction, String, null: true
    field :recommendation_type, String, null: true
    field :confidence, Float, null: true
    field :expected_return_min, Float, null: true
    field :expected_return_max, Float, null: true
    field :benchmark_symbol, String, null: true
    field :feature_version, String, null: true
    field :stock, Types::StockType, null: false
    field :report, Types::PredictionReportType, null: true
    field :outcome, Types::PredictionOutcomeType, null: true

    def as_of_date
      object.as_of_date.iso8601
    end

    def report
      object.prediction_report
    end

    def outcome
      object.prediction_outcome
    end
  end
end
