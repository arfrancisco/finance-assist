class AddUniqueConstraintToPredictions < ActiveRecord::Migration[7.1]
  def change
    add_index :predictions, [ :stock_id, :as_of_date, :horizon, :model_version_id ],
      unique: true,
      name: "index_predictions_unique"
  end
end
