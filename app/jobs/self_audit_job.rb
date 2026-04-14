class SelfAuditJob < ApplicationJob
  queue_as :default

  def perform
    count = Validation::SelfAudit.new.call
    Rails.logger.info("[SelfAuditJob] Completed: #{count} audit runs created")
  end
end
