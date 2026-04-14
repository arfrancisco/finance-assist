class ComputeFeaturesJob < ApplicationJob
  queue_as :default

  # Computes feature snapshots for all active stocks for the given date and all horizons.
  # Defaults to yesterday so it can be enqueued the morning after market close.
  def perform(as_of_date = Date.yesterday.to_s)
    as_of    = Date.parse(as_of_date.to_s)
    horizons = %w[5d 20d 60d]
    created  = 0

    Stock.where(is_active: true).find_each do |stock|
      horizons.each do |horizon|
        snapshot = Ranking::FeatureBuilder.new(stock: stock, as_of_date: as_of, horizon: horizon).call
        created += 1 if snapshot
      rescue => e
        Rails.logger.error("[ComputeFeaturesJob] Error for #{stock.symbol}/#{horizon}: #{e.message}")
      end
    end

    Rails.logger.info("[ComputeFeaturesJob] Completed: #{created} snapshots for #{as_of}")
  end
end
