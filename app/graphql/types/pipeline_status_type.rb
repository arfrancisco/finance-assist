module Types
  class PipelineStatusType < Types::BaseObject
    field :last_eodhd_sync, String, null: true
    field :last_pse_edge_sync, String, null: true
    field :latest_price_date, String, null: true
    field :latest_prediction_date, String, null: true
    field :latest_snapshot_date, String, null: true
    field :latest_audit_date, String, null: true
    field :stock_count, Integer, null: false
    field :active_stock_count, Integer, null: false
    field :price_count, Integer, null: false
    field :disclosure_count, Integer, null: false
    field :snapshot_count, Integer, null: false
    field :prediction_count, Integer, null: false
    field :report_count, Integer, null: false
    field :outcome_count, Integer, null: false
  end
end
