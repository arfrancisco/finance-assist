class EvaluateOutcomesJob < ApplicationJob
  queue_as :default

  def perform
    count = Validation::OutcomeEvaluator.new.call
    Rails.logger.info("[EvaluateOutcomesJob] Completed: #{count} outcomes evaluated")
  end
end
