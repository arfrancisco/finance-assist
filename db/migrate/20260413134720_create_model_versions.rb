class CreateModelVersions < ActiveRecord::Migration[7.1]
  def change
    create_table :model_versions do |t|
      t.string :version_name, null: false
      t.text :description
      t.string :algorithm_type
      t.jsonb :weights_json
      t.text :notes
      t.timestamps
    end

    add_index :model_versions, :version_name, unique: true
  end
end
