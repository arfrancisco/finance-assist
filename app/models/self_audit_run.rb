class SelfAuditRun < ApplicationRecord
  validates :run_date, presence: true
  validates :horizon, presence: true, inclusion: { in: %w[5d 20d 60d] }

  before_update { raise ActiveRecord::ReadOnlyRecord, "SelfAuditRuns are immutable." }

  scope :for_horizon, ->(h) { where(horizon: h).order(run_date: :desc) }
end
