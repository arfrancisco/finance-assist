class Stock < ApplicationRecord
  has_many :daily_prices, dependent: :destroy
  has_many :disclosures, dependent: :destroy
  has_many :corporate_actions, dependent: :destroy
  has_many :fundamentals, dependent: :destroy
  has_many :feature_snapshots, dependent: :destroy
  has_many :predictions, dependent: :destroy

  validates :symbol, presence: true, uniqueness: true

  scope :active, -> { where(is_active: true) }

  def to_s
    symbol
  end
end
