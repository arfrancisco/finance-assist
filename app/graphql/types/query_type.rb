require "ostruct"

module Types
  class QueryType < Types::BaseObject
    field :stocks, [Types::StockType], null: false do
      argument :sector, String, required: false
      argument :active_only, Boolean, required: false, default_value: true
    end

    field :stock, Types::StockType, null: true do
      argument :symbol, String, required: true
    end

    field :predictions, [Types::PredictionType], null: false do
      argument :horizon, String, required: false
      argument :date, String, required: false
      argument :limit, Integer, required: false, default_value: 20
    end

    field :self_audit_runs, [Types::SelfAuditRunType], null: false do
      argument :horizon, String, required: false
      argument :limit, Integer, required: false, default_value: 10
    end

    field :pipeline_status, Types::PipelineStatusType, null: false

    field :disclosures, [Types::DisclosureType], null: false do
      argument :symbol, String, required: false
      argument :disclosure_type, String, required: false
      argument :limit, Integer, required: false, default_value: 20
    end

    def stocks(sector: nil, active_only: true)
      scope = active_only ? Stock.active : Stock.all
      scope = scope.where(sector: sector) if sector.present?
      scope.order(:symbol)
    end

    def stock(symbol:)
      Stock.find_by(symbol: symbol.upcase)
    end

    def predictions(horizon: nil, date: nil, limit:)
      effective_date = if date.present?
        Date.parse(date)
      elsif horizon.present?
        Prediction.for_horizon(horizon).maximum(:as_of_date)
      else
        Prediction.maximum(:as_of_date)
      end

      return [] unless effective_date

      scope = Prediction.where(as_of_date: effective_date)
                        .includes(:stock, :prediction_report, :prediction_outcome)
      scope = scope.for_horizon(horizon) if horizon.present?
      scope.top_ranked(limit)
    end

    def self_audit_runs(horizon: nil, limit:)
      scope = SelfAuditRun.order(run_date: :desc)
      scope = scope.where(horizon: horizon) if horizon.present?
      scope.limit(limit)
    end

    def pipeline_status
      OpenStruct.new(
        last_eodhd_sync:        RawArtifact.where(source: "eodhd").maximum(:fetched_at)&.iso8601,
        last_pse_edge_sync:     Disclosure.maximum(:fetched_at)&.iso8601,
        latest_price_date:      DailyPrice.maximum(:trading_date)&.iso8601,
        latest_prediction_date: Prediction.maximum(:as_of_date)&.iso8601,
        latest_snapshot_date:   FeatureSnapshot.maximum(:as_of_date)&.iso8601,
        latest_audit_date:      SelfAuditRun.maximum(:run_date)&.iso8601,
        stock_count:            Stock.count,
        active_stock_count:     Stock.active.count,
        price_count:            DailyPrice.count,
        disclosure_count:       Disclosure.count,
        snapshot_count:         FeatureSnapshot.count,
        prediction_count:       Prediction.count,
        report_count:           PredictionReport.count,
        outcome_count:          PredictionOutcome.count
      )
    end

    def disclosures(symbol: nil, disclosure_type: nil, limit:)
      scope = Disclosure.all
      if symbol.present?
        scope = scope.joins(:stock).where(stocks: { symbol: symbol.upcase })
      end
      scope = scope.by_type(disclosure_type) if disclosure_type.present?
      scope.recent.limit(limit)
    end
  end
end
