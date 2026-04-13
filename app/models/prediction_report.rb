class PredictionReport < ApplicationRecord
  belongs_to :prediction

  validates :prompt_version, presence: true

  before_update { raise ActiveRecord::ReadOnlyRecord, "PredictionReports are immutable." }
end
