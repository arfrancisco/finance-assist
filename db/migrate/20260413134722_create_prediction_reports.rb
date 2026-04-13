class CreatePredictionReports < ActiveRecord::Migration[7.1]
  def change
    create_table :prediction_reports do |t|
      t.references :prediction, null: false, foreign_key: true, index: { unique: true }
      t.text :summary_text
      t.text :catalyst_text
      t.text :risk_text
      t.text :rationale_text
      t.string :llm_model
      t.string :prompt_version, null: false
      t.datetime :created_at, null: false
      # Immutable — no updated_at
    end

  end
end
