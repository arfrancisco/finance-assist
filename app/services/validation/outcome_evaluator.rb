module Validation
  # Evaluates past predictions whose horizon window has elapsed.
  # Compares entry vs exit price against the PSEi benchmark.
  # Creates immutable PredictionOutcome records.
  #
  # Horizon → trading days:
  #   short  → 5
  #   medium → 20
  #   long   → 60
  class OutcomeEvaluator
    HORIZON_DAYS = { "5d" => 5, "20d" => 20, "60d" => 60 }.freeze
    PSEI_SYMBOL  = "PSEI".freeze

    def call
      psei_stock = Stock.find_by(symbol: PSEI_SYMBOL)
      evaluated  = 0

      unevaluated_predictions.find_each do |prediction|
        horizon_days    = HORIZON_DAYS[prediction.horizon]
        evaluation_date = nearest_trading_date(prediction.as_of_date + horizon_days, prediction.stock)
        next unless evaluation_date

        entry = price_on(prediction.stock, prediction.as_of_date)
        exit  = price_on(prediction.stock, evaluation_date)

        unless entry && exit
          Rails.logger.warn("[OutcomeEvaluator] Missing prices for #{prediction.stock.symbol} (#{prediction.as_of_date}..#{evaluation_date}), skipping")
          next
        end

        raw_return = (exit / entry) - 1.0

        bench_entry = psei_stock ? price_on(psei_stock, prediction.as_of_date) : nil
        bench_exit  = psei_stock ? price_on(psei_stock, evaluation_date) : nil
        bench_return = (bench_entry && bench_exit) ? (bench_exit / bench_entry) - 1.0 : 0.0

        excess_return = raw_return - bench_return
        max_dd        = compute_max_drawdown(prediction.stock, prediction.as_of_date, evaluation_date)

        outcome_label = if excess_return > 0.01
          "win"
        elsif excess_return < -0.01
          "loss"
        else
          "neutral"
        end

        PredictionOutcome.create!(
          prediction:       prediction,
          evaluation_date:  evaluation_date,
          entry_price:      entry,
          exit_price:       exit,
          raw_return:       raw_return.round(6),
          benchmark_entry:  bench_entry,
          benchmark_exit:   bench_exit,
          benchmark_return: bench_return.round(6),
          excess_return:    excess_return.round(6),
          max_drawdown:     max_dd&.round(6),
          was_positive:     raw_return > 0,
          beat_benchmark:   excess_return > 0,
          outcome_label:    outcome_label
        )

        evaluated += 1
      rescue => e
        Rails.logger.error("[OutcomeEvaluator] Error for prediction #{prediction.id}: #{e.message}")
      end

      Rails.logger.info("[OutcomeEvaluator] Evaluated #{evaluated} predictions")
      evaluated
    end

    private

    def unevaluated_predictions
      Prediction
        .left_outer_joins(:prediction_outcome)
        .where(prediction_outcomes: { id: nil })
        .where("predictions.as_of_date + (CASE predictions.horizon WHEN '5d' THEN 5 WHEN '20d' THEN 20 WHEN '60d' THEN 60 END) <= ?", Date.today)
        .includes(:stock)
    end

    def price_on(stock, date)
      stock.daily_prices.find_by(trading_date: date)&.close&.to_f
    end

    # Find the nearest available trading date on or after the target date (up to 5 days)
    def nearest_trading_date(target_date, stock)
      5.times do |i|
        candidate = target_date + i
        return candidate if stock.daily_prices.exists?(trading_date: candidate)
      end
      nil
    end

    # Minimum cumulative return during the period (worst intraday point)
    def compute_max_drawdown(stock, from_date, to_date)
      prices = stock.daily_prices
                    .where(trading_date: from_date..to_date)
                    .order(:trading_date)
                    .pluck(:close)
                    .map(&:to_f)

      return nil if prices.size < 2

      entry  = prices.first
      min_dd = prices.map { |p| (p / entry) - 1.0 }.min
      min_dd
    end
  end
end
