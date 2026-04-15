module Ranking
  # Computes a FeatureSnapshot for a stock as of a given date and horizon.
  # Reads from daily_prices, fundamentals, and disclosures.
  # Upserts into feature_snapshots — safe to re-run.
  class FeatureBuilder
    FEATURE_VERSION = "v1".freeze
    MIN_PRICES = 20

    def initialize(stock:, as_of_date:, horizon:)
      @stock = stock
      @as_of_date = as_of_date.is_a?(Date) ? as_of_date : Date.parse(as_of_date.to_s)
      @horizon = horizon
    end

    # Returns the upserted FeatureSnapshot, or nil if insufficient data.
    # Idempotent on (stock_id, as_of_date, horizon) via upsert
    def call
      prices = load_prices
      if prices.size < MIN_PRICES
        Rails.logger.warn("[FeatureBuilder] #{@stock.symbol}: only #{prices.size} prices available (need #{MIN_PRICES}), skipping")
        return nil
      end

      attrs = compute_features(prices)
      upsert(attrs)
    end

    private

    def load_prices
      @stock.daily_prices
            .where("trading_date <= ?", @as_of_date)
            .order(trading_date: :desc)
            .limit(65)
            .to_a
            .reverse # oldest → newest
    end

    def compute_features(prices)
      closes = prices.map { |p| p.adjusted_close.to_f }
      volumes = prices.map { |p| p.volume.to_f }

      today_close = closes.last

      momentum_5d  = momentum(closes, 5)
      momentum_20d = momentum(closes, 20)
      momentum_60d = momentum(closes, 60)
      vol_20d      = volatility(closes, 20)
      avg_vol_20d  = volumes.last(20).sum / 20.0

      rs = relative_strength(momentum_20d)

      fund = latest_fundamental
      valuation = valuation_score(fund)
      quality    = quality_score(fund)

      catalyst = catalyst_score

      {
        stock_id:        @stock.id,
        as_of_date:      @as_of_date,
        horizon:         @horizon,
        feature_version: FEATURE_VERSION,
        momentum_5d:     momentum_5d,
        momentum_20d:    momentum_20d,
        momentum_60d:    momentum_60d,
        volatility_20d:  vol_20d,
        avg_volume_20d:  avg_vol_20d,
        relative_strength: rs,
        valuation_score: valuation,
        quality_score:   quality,
        liquidity_score: nil,  # Scorer fills in after cross-batch normalization
        catalyst_score:  catalyst,
        risk_score:      vol_20d,      # raw — Scorer normalizes across batch
        total_score:     nil,
        created_at:      Time.current,
        updated_at:      Time.current
      }
    end

    # (close_today / close_n_ago) - 1
    def momentum(closes, n)
      return nil if closes.size < n + 1
      past = closes[-(n + 1)]
      return nil if past.nil? || past.zero?
      (closes.last / past) - 1.0
    end

    # Std dev of log returns over last n days
    def volatility(closes, n)
      return nil if closes.size < n + 1
      window = closes.last(n + 1)
      log_returns = window.each_cons(2).map { |a, b| Math.log(b / a) }
      mean = log_returns.sum / log_returns.size
      variance = log_returns.sum { |r| (r - mean)**2 } / log_returns.size
      Math.sqrt(variance)
    end

    def relative_strength(stock_momentum_20d)
      return 0.0 if stock_momentum_20d.nil?
      psei = Stock.find_by(symbol: "PSEI")
      return stock_momentum_20d if psei.nil?

      psei_prices = psei.daily_prices
                        .where("trading_date <= ?", @as_of_date)
                        .order(trading_date: :desc)
                        .limit(22)
                        .pluck(:adjusted_close)
                        .reverse
                        .map(&:to_f)

      psei_momentum = if psei_prices.size >= 21
        past = psei_prices[-21]
        past.zero? ? 0.0 : (psei_prices.last / past) - 1.0
      else
        0.0
      end

      stock_momentum_20d - psei_momentum
    end

    def latest_fundamental
      @stock.fundamentals
            .where("period_end_date <= ?", @as_of_date)
            .order(period_end_date: :desc)
            .first
    end

    # Lower PE → higher score. Normalize to 0–1 using 1/PE, capped.
    def valuation_score(fund)
      return nil if fund.nil? || fund.pe.nil? || fund.pe <= 0
      raw = 1.0 / fund.pe.to_f
      # Typical 1/PE for PSE stocks: 0 to ~0.15 (PE 7 to infinity)
      [raw / 0.15, 1.0].min
    end

    # ROE normalized to 0–1. Cap at 30% ROE = score 1.
    def quality_score(fund)
      return nil if fund.nil? || fund.roe.nil?
      roe = fund.roe.to_f
      return 0.0 if roe <= 0
      [roe / 30.0, 1.0].min
    end

    # Disclosures in last 30 days, capped at 5 → 0–1
    def catalyst_score
      count = @stock.disclosures
                    .where("disclosure_date >= ?", @as_of_date - 30)
                    .count
      [count, 5].min / 5.0
    end

    def upsert(attrs)
      result = FeatureSnapshot.upsert(
        attrs,
        unique_by: [ :stock_id, :as_of_date, :horizon ],
        update_only: %i[
          momentum_5d momentum_20d momentum_60d
          volatility_20d avg_volume_20d relative_strength
          valuation_score quality_score liquidity_score
          catalyst_score risk_score total_score
          feature_version
        ]
      )

      FeatureSnapshot.find_by(
        stock_id:   @stock.id,
        as_of_date: @as_of_date,
        horizon:    @horizon
      )
    end
  end
end
