class CreateDisclosures < ActiveRecord::Migration[7.1]
  def change
    create_table :disclosures do |t|
      t.references :stock, null: false, foreign_key: true
      t.string :disclosure_type
      t.string :title
      t.text :body_text
      t.date :disclosure_date
      t.string :source_url
      t.string :source_id
      t.datetime :fetched_at
      t.jsonb :raw_payload
      t.timestamps
    end

    add_index :disclosures, [ :stock_id, :disclosure_date ]
    add_index :disclosures, :source_id
    add_index :disclosures, :raw_payload, using: :gin
  end
end
