class SelfAuditJob < ApplicationJob
  queue_as :default

  # Generates weekly self-audit summaries comparing predictions to outcomes.
  # Stub — implemented in Phase 4.
  def perform
    Rails.logger.info("[SelfAuditJob] Self-audit not yet implemented (Phase 4).")
    # TODO Phase 4: Validation::SelfAudit.new.call
  end
end
