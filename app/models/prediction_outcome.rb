class PredictionOutcome < ApplicationRecord
  belongs_to :prediction

  validates :evaluation_date, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "PredictionOutcomes are immutable." }
end
