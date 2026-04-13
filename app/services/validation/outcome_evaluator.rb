module Validation
  # Evaluates past predictions whose horizon window has elapsed.
  # Stub — implemented in Phase 4.
  #
  # Phase 4 will:
  # - Find predictions with no outcome where as_of_date + horizon_days <= today
  # - Look up entry price (close on as_of_date) and exit price (close on evaluation_date)
  # - Fetch benchmark (PSEi) prices for the same period
  # - Compute raw_return, benchmark_return, excess_return, max_drawdown
  # - Create PredictionOutcome records (immutable)
  class OutcomeEvaluator
    def call
      raise NotImplementedError, "OutcomeEvaluator is not yet implemented. See Phase 4."
    end
  end
end
