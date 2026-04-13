class CreateCorporateActions < ActiveRecord::Migration[7.1]
  def change
    create_table :corporate_actions do |t|
      t.references :stock, null: false, foreign_key: true
      t.string :action_type, null: false
      t.date :announced_date
      t.date :ex_date
      t.date :record_date
      t.date :payment_date
      t.text :description
      t.decimal :value, precision: 15, scale: 6
      t.string :source_url
      t.timestamps
    end

    add_index :corporate_actions, [ :stock_id, :action_type, :ex_date ]
  end
end
