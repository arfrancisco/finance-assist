module Types
  class PredictionOutcomeType < Types::BaseObject
    field :id, ID, null: false
    field :evaluation_date, String, null: false
    field :entry_price, Float, null: true
    field :exit_price, Float, null: true
    field :raw_return, Float, null: true
    field :benchmark_return, Float, null: true
    field :excess_return, Float, null: true
    field :max_drawdown, Float, null: true
    field :was_positive, Boolean, null: true
    field :beat_benchmark, Boolean, null: true
    field :outcome_label, String, null: true

    def evaluation_date
      object.evaluation_date.iso8601
    end
  end
end
