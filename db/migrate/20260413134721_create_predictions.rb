class CreatePredictions < ActiveRecord::Migration[7.1]
  def change
    create_table :predictions do |t|
      t.references :stock, null: false, foreign_key: true
      t.references :model_version, null: false, foreign_key: true
      t.date :as_of_date, null: false
      t.string :horizon, null: false
      t.string :recommendation_type
      t.integer :rank_position
      t.decimal :predicted_probability, precision: 10, scale: 6
      t.string :predicted_direction
      t.decimal :expected_return_min, precision: 10, scale: 6
      t.decimal :expected_return_max, precision: 10, scale: 6
      t.decimal :confidence, precision: 10, scale: 6
      t.decimal :total_score, null: false, precision: 10, scale: 6
      t.string :benchmark_symbol
      t.string :feature_version
      t.datetime :created_at, null: false
      # Intentionally no updated_at — predictions are immutable historical records
    end

    add_index :predictions, [ :as_of_date, :horizon ]
    add_index :predictions, [ :stock_id, :as_of_date, :horizon ]
  end
end
