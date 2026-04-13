class CreatePredictionOutcomes < ActiveRecord::Migration[7.1]
  def change
    create_table :prediction_outcomes do |t|
      t.references :prediction, null: false, foreign_key: true, index: { unique: true }
      t.date :evaluation_date, null: false
      t.decimal :entry_price, precision: 15, scale: 6
      t.decimal :exit_price, precision: 15, scale: 6
      t.decimal :raw_return, precision: 10, scale: 6
      t.decimal :benchmark_entry, precision: 15, scale: 6
      t.decimal :benchmark_exit, precision: 15, scale: 6
      t.decimal :benchmark_return, precision: 10, scale: 6
      t.decimal :excess_return, precision: 10, scale: 6
      t.decimal :max_drawdown, precision: 10, scale: 6
      t.boolean :was_positive
      t.boolean :beat_benchmark
      t.string :outcome_label
      t.datetime :created_at, null: false
      # Immutable — no updated_at
    end

  end
end
