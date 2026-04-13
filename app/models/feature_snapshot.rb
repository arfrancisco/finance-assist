class FeatureSnapshot < ApplicationRecord
  belongs_to :stock

  validates :as_of_date, presence: true
  validates :horizon, presence: true, inclusion: { in: %w[short medium long] }
  validates :feature_version, presence: true
  validates :as_of_date, uniqueness: { scope: [ :stock_id, :horizon ] }
end
