class Disclosure < ApplicationRecord
  belongs_to :stock

  validates :disclosure_date, presence: true

  scope :recent, -> { order(disclosure_date: :desc) }
  scope :by_type, ->(type) { where(disclosure_type: type) }
end
