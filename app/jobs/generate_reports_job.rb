class GenerateReportsJob < ApplicationJob
  queue_as :default

  # Generates LLM research reports for top-ranked predictions on a given date.
  # Skips predictions that already have a report.
  def perform(as_of_date = Date.yesterday.to_s, horizon = nil, top = 10)
    as_of    = Date.parse(as_of_date.to_s)
    horizons = horizon ? [ horizon ] : %w[short medium long]
    client   = Reporting::Llm::Client.build
    total    = 0

    horizons.each do |h|
      predictions = Prediction.for_date(as_of)
                              .for_horizon(h)
                              .top_ranked(top)
                              .includes(:stock, :prediction_report)
                              .select { |p| p.prediction_report.nil? }

      predictions.each do |prediction|
        Reporting::ReportGenerator.new(prediction, llm_client: client).call
        total += 1
        sleep 1  # avoid rate limits
      rescue => e
        Rails.logger.error("[GenerateReportsJob] Error for prediction #{prediction.id}: #{e.message}")
      end
    end

    Rails.logger.info("[GenerateReportsJob] Generated #{total} reports for #{as_of}")
  end
end
