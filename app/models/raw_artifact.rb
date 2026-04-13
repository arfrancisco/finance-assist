class RawArtifact < ApplicationRecord
  validates :source, presence: true
  validates :fetched_at, presence: true

  scope :for_source, ->(src) { where(source: src).order(fetched_at: :desc) }
end
