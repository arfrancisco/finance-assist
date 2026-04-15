module Types
  class FeatureSnapshotType < Types::BaseObject
    field :id, ID, null: false
    field :as_of_date, String, null: false
    field :horizon, String, null: false
    field :feature_version, String, null: false
    field :momentum_5d, Float, null: true
    field :momentum_20d, Float, null: true
    field :momentum_60d, Float, null: true
    field :volatility_20d, Float, null: true
    field :avg_volume_20d, Float, null: true
    field :relative_strength, Float, null: true
    field :valuation_score, Float, null: true
    field :quality_score, Float, null: true
    field :liquidity_score, Float, null: true
    field :catalyst_score, Float, null: true
    field :risk_score, Float, null: true
    field :total_score, Float, null: true

    def as_of_date
      object.as_of_date.iso8601
    end
  end
end
