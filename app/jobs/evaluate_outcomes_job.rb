class EvaluateOutcomesJob < ApplicationJob
  queue_as :default

  # Evaluates past predictions whose horizon window has elapsed.
  # Stub — implemented in Phase 4.
  def perform
    Rails.logger.info("[EvaluateOutcomesJob] Outcome evaluation not yet implemented (Phase 4).")
    # TODO Phase 4: Validation::OutcomeEvaluator.new.call
  end
end
