class SelfAuditsController < ApplicationController
  def index
    # Most recent 20 audit runs across all horizons, newest first
    @audit_runs = SelfAuditRun.order(run_date: :desc, horizon: :asc).limit(20)
  end
end
