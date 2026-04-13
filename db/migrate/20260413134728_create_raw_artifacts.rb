class CreateRawArtifacts < ActiveRecord::Migration[7.1]
  def change
    create_table :raw_artifacts do |t|
      t.string :source, null: false
      t.string :source_url
      t.string :payload_location
      t.string :checksum
      t.datetime :fetched_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :raw_artifacts, [ :source, :fetched_at ]
    add_index :raw_artifacts, :checksum
  end
end
