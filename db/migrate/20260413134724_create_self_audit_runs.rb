class CreateSelfAuditRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :self_audit_runs do |t|
      t.date :run_date, null: false
      t.string :horizon, null: false
      t.integer :sample_size
      t.decimal :hit_rate, precision: 10, scale: 6
      t.decimal :avg_return, precision: 10, scale: 6
      t.decimal :avg_excess_return, precision: 10, scale: 6
      t.decimal :brier_score, precision: 10, scale: 6
      t.text :calibration_notes
      t.text :summary_text
      t.datetime :created_at, null: false
    end

    add_index :self_audit_runs, [ :run_date, :horizon ]
  end
end
