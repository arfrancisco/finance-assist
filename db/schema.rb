# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_14_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "corporate_actions", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.string "action_type", null: false
    t.date "announced_date"
    t.date "ex_date"
    t.date "record_date"
    t.date "payment_date"
    t.text "description"
    t.decimal "value", precision: 15, scale: 6
    t.string "source_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id", "action_type", "ex_date"], name: "idx_on_stock_id_action_type_ex_date_20ba3db3b3"
    t.index ["stock_id"], name: "index_corporate_actions_on_stock_id"
  end

  create_table "daily_prices", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.date "trading_date", null: false
    t.decimal "open", precision: 15, scale: 6
    t.decimal "high", precision: 15, scale: 6
    t.decimal "low", precision: 15, scale: 6
    t.decimal "close", precision: 15, scale: 6, null: false
    t.decimal "adjusted_close", precision: 15, scale: 6
    t.bigint "volume"
    t.decimal "traded_value", precision: 20, scale: 6
    t.string "source"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id", "trading_date"], name: "index_daily_prices_on_stock_id_and_trading_date", unique: true
    t.index ["stock_id"], name: "index_daily_prices_on_stock_id"
    t.index ["trading_date"], name: "index_daily_prices_on_trading_date"
  end

  create_table "disclosures", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.string "disclosure_type"
    t.string "title"
    t.text "body_text"
    t.date "disclosure_date"
    t.string "source_url"
    t.string "source_id"
    t.datetime "fetched_at"
    t.jsonb "raw_payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["raw_payload"], name: "index_disclosures_on_raw_payload", using: :gin
    t.index ["source_id"], name: "index_disclosures_on_source_id"
    t.index ["stock_id", "disclosure_date"], name: "index_disclosures_on_stock_id_and_disclosure_date"
    t.index ["stock_id"], name: "index_disclosures_on_stock_id"
  end

  create_table "feature_snapshots", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.date "as_of_date", null: false
    t.string "horizon", null: false
    t.decimal "momentum_5d", precision: 10, scale: 6
    t.decimal "momentum_20d", precision: 10, scale: 6
    t.decimal "momentum_60d", precision: 10, scale: 6
    t.decimal "volatility_20d", precision: 10, scale: 6
    t.decimal "avg_volume_20d", precision: 20, scale: 2
    t.decimal "relative_strength", precision: 10, scale: 6
    t.decimal "valuation_score", precision: 10, scale: 6
    t.decimal "quality_score", precision: 10, scale: 6
    t.decimal "liquidity_score", precision: 10, scale: 6
    t.decimal "catalyst_score", precision: 10, scale: 6
    t.decimal "risk_score", precision: 10, scale: 6
    t.decimal "total_score", precision: 10, scale: 6
    t.string "feature_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id", "as_of_date", "horizon"], name: "idx_feature_snapshots_stock_date_horizon", unique: true
    t.index ["stock_id"], name: "index_feature_snapshots_on_stock_id"
  end

  create_table "fundamentals", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.string "period_type", null: false
    t.date "period_end_date", null: false
    t.decimal "revenue", precision: 20, scale: 2
    t.decimal "net_income", precision: 20, scale: 2
    t.decimal "eps", precision: 15, scale: 6
    t.decimal "book_value", precision: 15, scale: 6
    t.decimal "debt", precision: 20, scale: 2
    t.decimal "cash", precision: 20, scale: 2
    t.decimal "pe", precision: 15, scale: 6
    t.decimal "pb", precision: 15, scale: 6
    t.decimal "dividend_yield", precision: 10, scale: 6
    t.decimal "roe", precision: 10, scale: 6
    t.decimal "roa", precision: 10, scale: 6
    t.string "source"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_id", "period_type", "period_end_date"], name: "idx_fundamentals_stock_period", unique: true
    t.index ["stock_id"], name: "index_fundamentals_on_stock_id"
  end

  create_table "model_versions", force: :cascade do |t|
    t.string "version_name", null: false
    t.text "description"
    t.string "algorithm_type"
    t.jsonb "weights_json"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["version_name"], name: "index_model_versions_on_version_name", unique: true
  end

  create_table "prediction_outcomes", force: :cascade do |t|
    t.bigint "prediction_id", null: false
    t.date "evaluation_date", null: false
    t.decimal "entry_price", precision: 15, scale: 6
    t.decimal "exit_price", precision: 15, scale: 6
    t.decimal "raw_return", precision: 10, scale: 6
    t.decimal "benchmark_entry", precision: 15, scale: 6
    t.decimal "benchmark_exit", precision: 15, scale: 6
    t.decimal "benchmark_return", precision: 10, scale: 6
    t.decimal "excess_return", precision: 10, scale: 6
    t.decimal "max_drawdown", precision: 10, scale: 6
    t.boolean "was_positive"
    t.boolean "beat_benchmark"
    t.string "outcome_label"
    t.datetime "created_at", null: false
    t.index ["prediction_id"], name: "index_prediction_outcomes_on_prediction_id", unique: true
  end

  create_table "prediction_reports", force: :cascade do |t|
    t.bigint "prediction_id", null: false
    t.text "summary_text"
    t.text "catalyst_text"
    t.text "risk_text"
    t.text "rationale_text"
    t.string "llm_model"
    t.string "prompt_version", null: false
    t.datetime "created_at", null: false
    t.index ["prediction_id"], name: "index_prediction_reports_on_prediction_id", unique: true
  end

  create_table "predictions", force: :cascade do |t|
    t.bigint "stock_id", null: false
    t.bigint "model_version_id", null: false
    t.date "as_of_date", null: false
    t.string "horizon", null: false
    t.string "recommendation_type"
    t.integer "rank_position"
    t.decimal "predicted_probability", precision: 10, scale: 6
    t.string "predicted_direction"
    t.decimal "expected_return_min", precision: 10, scale: 6
    t.decimal "expected_return_max", precision: 10, scale: 6
    t.decimal "confidence", precision: 10, scale: 6
    t.decimal "total_score", precision: 10, scale: 6, null: false
    t.string "benchmark_symbol"
    t.string "feature_version"
    t.datetime "created_at", null: false
    t.index ["as_of_date", "horizon"], name: "index_predictions_on_as_of_date_and_horizon"
    t.index ["model_version_id"], name: "index_predictions_on_model_version_id"
    t.index ["stock_id", "as_of_date", "horizon"], name: "index_predictions_on_stock_id_and_as_of_date_and_horizon"
    t.index ["stock_id"], name: "index_predictions_on_stock_id"
  end

  create_table "raw_artifacts", force: :cascade do |t|
    t.string "source", null: false
    t.string "source_url"
    t.string "payload_location"
    t.string "checksum"
    t.datetime "fetched_at", null: false
    t.datetime "created_at", null: false
    t.index ["checksum"], name: "index_raw_artifacts_on_checksum"
    t.index ["source", "fetched_at"], name: "index_raw_artifacts_on_source_and_fetched_at"
  end

  create_table "self_audit_runs", force: :cascade do |t|
    t.date "run_date", null: false
    t.string "horizon", null: false
    t.integer "sample_size"
    t.decimal "hit_rate", precision: 10, scale: 6
    t.decimal "avg_return", precision: 10, scale: 6
    t.decimal "avg_excess_return", precision: 10, scale: 6
    t.decimal "brier_score", precision: 10, scale: 6
    t.text "calibration_notes"
    t.text "summary_text"
    t.datetime "created_at", null: false
    t.jsonb "metrics_json"
    t.index ["run_date", "horizon"], name: "index_self_audit_runs_on_run_date_and_horizon"
  end

  create_table "stocks", force: :cascade do |t|
    t.string "symbol", null: false
    t.string "company_name"
    t.string "sector"
    t.string "industry"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_active"], name: "index_stocks_on_is_active"
    t.index ["symbol"], name: "index_stocks_on_symbol", unique: true
  end

  add_foreign_key "corporate_actions", "stocks"
  add_foreign_key "daily_prices", "stocks"
  add_foreign_key "disclosures", "stocks"
  add_foreign_key "feature_snapshots", "stocks"
  add_foreign_key "fundamentals", "stocks"
  add_foreign_key "prediction_outcomes", "predictions"
  add_foreign_key "prediction_reports", "predictions"
  add_foreign_key "predictions", "model_versions"
  add_foreign_key "predictions", "stocks"
end
