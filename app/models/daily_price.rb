class DailyPrice < ApplicationRecord
  belongs_to :stock

  validates :trading_date, presence: true
  validates :close, presence: true, numericality: true
  validates :trading_date, uniqueness: { scope: :stock_id }

  scope :for_date, ->(date) { where(trading_date: date) }
  scope :between, ->(from, to) { where(trading_date: from..to).order(:trading_date) }
end
