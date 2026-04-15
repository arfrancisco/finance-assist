module Types
  class StockType < Types::BaseObject
    field :id, ID, null: false
    field :symbol, String, null: false
    field :company_name, String, null: true
    field :sector, String, null: true
    field :industry, String, null: true
    field :is_active, Boolean, null: false

    field :recent_prices, [Types::DailyPriceType], null: false do
      argument :limit, Integer, required: false, default_value: 10
    end

    field :latest_snapshot, Types::FeatureSnapshotType, null: true do
      argument :horizon, String, required: false, default_value: "20d"
    end

    field :latest_predictions, [Types::PredictionType], null: false do
      argument :horizon, String, required: false
      argument :limit, Integer, required: false, default_value: 3
    end

    field :recent_disclosures, [Types::DisclosureType], null: false do
      argument :limit, Integer, required: false, default_value: 5
    end

    def recent_prices(limit:)
      object.daily_prices.order(trading_date: :desc).limit(limit)
    end

    def latest_snapshot(horizon:)
      object.feature_snapshots
            .where(horizon: horizon)
            .order(as_of_date: :desc)
            .first
    end

    def latest_predictions(horizon: nil, limit:)
      scope = object.predictions
                    .includes(:prediction_report, :prediction_outcome)
                    .order(as_of_date: :desc, rank_position: :asc)
      scope = scope.for_horizon(horizon) if horizon.present?
      scope.limit(limit)
    end

    def recent_disclosures(limit:)
      object.disclosures.recent.limit(limit)
    end
  end
end
