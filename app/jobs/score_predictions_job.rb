class ScorePredictionsJob < ApplicationJob
  queue_as :default

  # Scores all feature snapshots for the given date using the named model version.
  # Defaults to yesterday and the v1 model.
  def perform(as_of_date = Date.yesterday.to_s, model_version_name = "v1")
    as_of         = Date.parse(as_of_date.to_s)
    model_version = ModelVersion.find_by!(version_name: model_version_name)
    snapshots     = FeatureSnapshot.where(as_of_date: as_of).to_a

    scorer      = Ranking::Scorer.new(model_version: model_version)
    predictions = scorer.call_batch(feature_snapshots: snapshots)

    Rails.logger.info("[ScorePredictionsJob] Completed: #{predictions.compact.size} new predictions for #{as_of} using #{model_version_name}")
  end
end
