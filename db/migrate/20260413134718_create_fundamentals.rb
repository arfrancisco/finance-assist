class CreateFundamentals < ActiveRecord::Migration[7.1]
  def change
    create_table :fundamentals do |t|
      t.references :stock, null: false, foreign_key: true
      t.string :period_type, null: false
      t.date :period_end_date, null: false
      t.decimal :revenue, precision: 20, scale: 2
      t.decimal :net_income, precision: 20, scale: 2
      t.decimal :eps, precision: 15, scale: 6
      t.decimal :book_value, precision: 15, scale: 6
      t.decimal :debt, precision: 20, scale: 2
      t.decimal :cash, precision: 20, scale: 2
      t.decimal :pe, precision: 15, scale: 6
      t.decimal :pb, precision: 15, scale: 6
      t.decimal :dividend_yield, precision: 10, scale: 6
      t.decimal :roe, precision: 10, scale: 6
      t.decimal :roa, precision: 10, scale: 6
      t.string :source
      t.datetime :fetched_at
      t.timestamps
    end

    add_index :fundamentals, [ :stock_id, :period_type, :period_end_date ], unique: true, name: "idx_fundamentals_stock_period"
  end
end
