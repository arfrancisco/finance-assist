class AddUniqueConstraintToSelfAuditRuns < ActiveRecord::Migration[7.1]
  def change
    add_index :self_audit_runs, [ :run_date, :horizon ],
      unique: true,
      name: "index_self_audit_runs_unique"
  end
end
