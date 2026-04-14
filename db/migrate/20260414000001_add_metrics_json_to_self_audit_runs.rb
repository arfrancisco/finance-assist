class AddMetricsJsonToSelfAuditRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :self_audit_runs, :metrics_json, :jsonb
  end
end
