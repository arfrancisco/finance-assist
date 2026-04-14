class Prediction < ApplicationRecord
  belongs_to :stock
  belongs_to :model_version
  has_one :prediction_report, dependent: :destroy
  has_one :prediction_outcome, dependent: :destroy

  validates :as_of_date, presence: true
  validates :horizon, presence: true, inclusion: { in: %w[5d 20d 60d] }
  validates :total_score, presence: true, numericality: true

  # Predictions are immutable — Rails will raise ActiveRecord::ReadOnlyRecord on any update attempt.
  # All attributes including rank_position are set before the record is first persisted.
  def readonly?
    persisted?
  end

  scope :for_horizon, ->(h) { where(horizon: h) }
  scope :for_date, ->(date) { where(as_of_date: date) }
  scope :top_ranked, ->(n = 10) { where.not(rank_position: nil).order(:rank_position).limit(n) }
end
