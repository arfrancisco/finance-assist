class CreateStocks < ActiveRecord::Migration[7.1]
  def change
    create_table :stocks do |t|
      t.string :symbol, null: false
      t.string :company_name
      t.string :sector
      t.string :industry
      t.boolean :is_active, null: false, default: true
      t.timestamps
    end

    add_index :stocks, :symbol, unique: true
    add_index :stocks, :is_active
  end
end
