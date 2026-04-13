class IngestPseEdgeJob < ApplicationJob
  queue_as :default

  # Fetches the latest PSE EDGE disclosures.
  # Triggered daily, or manually via rake task.
  def perform(pages: 2)
    Rails.logger.info("[IngestPseEdgeJob] Starting PSE EDGE disclosure ingest (#{pages} page(s))")
    importer = Disclosures::PseEdge::Importer.new(pages: pages)
    count = importer.call
    Rails.logger.info("[IngestPseEdgeJob] Done. #{count} new disclosures imported.")
  end
end
