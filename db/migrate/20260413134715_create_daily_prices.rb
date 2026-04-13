class CreateDailyPrices < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_prices do |t|
      t.references :stock, null: false, foreign_key: true
      t.date :trading_date, null: false
      t.decimal :open, precision: 15, scale: 6
      t.decimal :high, precision: 15, scale: 6
      t.decimal :low, precision: 15, scale: 6
      t.decimal :close, null: false, precision: 15, scale: 6
      t.decimal :adjusted_close, precision: 15, scale: 6
      t.bigint :volume
      t.decimal :traded_value, precision: 20, scale: 6
      t.string :source
      t.datetime :fetched_at
      t.timestamps
    end

    add_index :daily_prices, [ :stock_id, :trading_date ], unique: true
    add_index :daily_prices, :trading_date
  end
end
