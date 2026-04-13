class Fundamental < ApplicationRecord
  belongs_to :stock

  validates :period_type, presence: true
  validates :period_end_date, presence: true
  validates :period_end_date, uniqueness: { scope: [ :stock_id, :period_type ] }

  PERIOD_TYPES = %w[annual quarterly].freeze
end
