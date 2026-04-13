class CreateFeatureSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :feature_snapshots do |t|
      t.references :stock, null: false, foreign_key: true
      t.date :as_of_date, null: false
      t.string :horizon, null: false
      t.decimal :momentum_5d, precision: 10, scale: 6
      t.decimal :momentum_20d, precision: 10, scale: 6
      t.decimal :momentum_60d, precision: 10, scale: 6
      t.decimal :volatility_20d, precision: 10, scale: 6
      t.decimal :avg_volume_20d, precision: 20, scale: 2
      t.decimal :relative_strength, precision: 10, scale: 6
      t.decimal :valuation_score, precision: 10, scale: 6
      t.decimal :quality_score, precision: 10, scale: 6
      t.decimal :liquidity_score, precision: 10, scale: 6
      t.decimal :catalyst_score, precision: 10, scale: 6
      t.decimal :risk_score, precision: 10, scale: 6
      t.decimal :total_score, precision: 10, scale: 6
      t.string :feature_version, null: false
      t.timestamps
    end

    add_index :feature_snapshots, [ :stock_id, :as_of_date, :horizon ], unique: true, name: "idx_feature_snapshots_stock_date_horizon"
  end
end
