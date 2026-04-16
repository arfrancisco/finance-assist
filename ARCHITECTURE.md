# Architecture: finance-assist

## Service layer map

```
app/services/
├── market_data/
│   ├── provider.rb                        # Abstract interface (Phase 1)
│   ├── providers/
│   │   └── eodhd_client.rb                # EODHD API client — bulk EOD + index (Phase 1)
│   └── importers/
│       ├── symbols_importer.rb            # PSE symbol list → stocks (Phase 1)
│       ├── eod_prices_importer.rb         # OHLCV → daily_prices (Phase 1)
│       └── corporate_actions_importer.rb  # Dividends → corporate_actions (Phase 1)
│
├── disclosures/
│   └── pse_edge/
│       ├── fetcher.rb                     # Rate-limited HTTP client (Phase 1)
│       ├── listing_parser.rb              # Nokogiri: listing page → rows (Phase 1)
│       ├── detail_parser.rb               # Nokogiri: detail page → body + attachments (Phase 1)
│       ├── attachment_downloader.rb       # PDF download for new disclosures (Phase 1)
│       └── importer.rb                    # Orchestrates full sweep (Phase 1)
│
├── ranking/
│   ├── feature_builder.rb                 # Momentum, volatility, RS, factor scores (Phase 2)
│   ├── scorer.rb                          # Z-score normalization + weighted scoring → predictions (Phase 2)
│   └── weight_tuner.rb                    # Outcome-driven weight retuning → new ModelVersion (Phase 5)
│
├── reporting/
│   ├── llm/
│   │   ├── client.rb                      # Abstract + factory (Phase 1)
│   │   ├── anthropic_client.rb            # Claude via Faraday + prompt caching (Phase 1)
│   │   └── openai_client.rb               # GPT-4o via Faraday (Phase 1)
│   └── report_generator.rb                # Structured LLM prompt → prediction_reports (Phase 3)
│
└── validation/
    ├── outcome_evaluator.rb               # Entry/exit prices vs PSEi → prediction_outcomes (Phase 4)
    └── self_audit.rb                      # Hit rate, Brier score, excess return → self_audit_runs (Phase 4)

app/graphql/                               # Read-only GraphQL API (Phase 6)
├── finance_assist_schema.rb               # Root schema (no mutations, max_depth 10)
└── types/
    ├── query_type.rb                      # Root query fields
    ├── stock_type.rb                      # Stock + nested prices/predictions/disclosures/snapshot
    ├── daily_price_type.rb
    ├── disclosure_type.rb
    ├── feature_snapshot_type.rb
    ├── prediction_type.rb                 # + nested report/outcome
    ├── prediction_report_type.rb
    ├── prediction_outcome_type.rb
    ├── self_audit_run_type.rb
    └── pipeline_status_type.rb            # OpenStruct-backed system health

mcp-server/                                # Local Node.js MCP server (Phase 6)
├── index.js                               # MCP stdio transport, tool registry
├── graphql-client.js                      # Authenticated fetch → POST /graphql
└── tools/
    ├── get_pipeline_status.js
    ├── list_stocks.js
    ├── get_stock.js
    ├── get_top_predictions.js
    ├── get_self_audit.js
    └── search_disclosures.js
```

## Data flow

```
EODHD API
  → EodhdClient (bulk endpoint: 1 API call for full PSE exchange)
  → raw JSON saved to data/raw/eodhd/ + raw_artifacts table
  → Importers → stocks, daily_prices, corporate_actions, fundamentals
  → EodhdClient (index endpoint: 1 API call/day) → daily_prices (PSEI benchmark)

PSE EDGE
  → PseEdge::Fetcher (rate-limited: 2s floor, 50 req/run cap)
  → raw HTML/PDFs saved to data/raw/pse_edge/ + raw_artifacts table
  → ListingParser + DetailParser
  → PseEdge::Importer → disclosures

[Phase 2]
  daily_prices + disclosures + fundamentals
    → FeatureBuilder (per stock × per horizon) → feature_snapshots
    → Scorer (z-score normalization + model_version.weights_json) → predictions (immutable)

[Phase 3]
  Prediction + FeatureSnapshot + recent disclosures
    → ReportGenerator (structured LLM prompt, prompt cached on Anthropic)
    → prediction_reports (immutable, llm_model + prompt_version recorded)

[Phase 4]
  Prediction + post-horizon daily_prices + PSEi prices
    → OutcomeEvaluator → prediction_outcomes (raw_return, excess_return, beat_benchmark)
  PredictionOutcome aggregates
    → SelfAudit → self_audit_runs (hit_rate, avg_return, brier_score per horizon)

[Phase 5]
  PredictionOutcome × FeatureSnapshot correlations
    → WeightTuner → new ModelVersion (e.g. v2) with retuned weights_json
  Run finance:score_predictions MODEL=v2 to use new weights going forward
```

```
[Phase 6 — External access, read-only]
  Claude Code (local)
    → MCP stdio transport → mcp-server/index.js
    → POST /graphql + Authorization: Bearer <MCP_API_KEY>
    → GraphqlController (401 if key missing/wrong)
    → FinanceAssistSchema (read-only, no mutations, max_depth 10)
    → PostgreSQL (same DB, read-only queries)
```

## Key design decisions

| Decision | Rationale |
|----------|-----------|
| Provider abstraction for market data | EODHD can be replaced by PSE FTP or another vendor without changing importers |
| Bulk EODHD endpoint | 1 API call for full PSE exchange vs. 1 per symbol (paid plan required for bulk) |
| Predictions are immutable | Enables honest backtesting; old predictions cannot be retroactively improved |
| `raw_artifacts` table | Auditability — every API call and page fetch is traceable to a file on disk |
| PSE EDGE rate limit (2s floor, 50 req cap) | Respectful crawling; only pages already shown to users |
| solid_queue (Postgres-backed) | No Redis dependency; fits Railway free tier; portable to Render |
| LLM provider abstraction | Swap Claude ↔ GPT-4o via `LLM_PROVIDER` env var without code changes |
| Prompt caching on Anthropic system block | Reduces cost when the same system prompt is reused across multiple report generations |
| Z-score normalization in Scorer | Cross-stock feature comparison is scale-independent |
| Per-horizon factor weights | 5d/20d/60d horizons weight momentum vs. value differently |
| WeightTuner is advisory | Creates a new ModelVersion but doesn't auto-switch — explicit `MODEL=v2` opt-in |
| GraphQL over REST for MCP | Single endpoint, self-describing schema, flexible field selection — Claude can request exactly what it needs |
| MCP server runs locally (stdio) | Secrets stay on the local machine; the remote endpoint is protected by API key; no server-to-server auth complexity |
| Stocks index uses correlated subqueries | After backfilling 300k+ price rows, `includes` loaded the full table into Ruby memory. Correlated subqueries compute counts and latest price in SQL, backed by the `(stock_id, trading_date)` unique index. |
| Dashboard counts cached via `Rails.cache` | Full-table COUNTs on large tables are expensive. Counts are cached for 5 minutes; freshness indicators (`maximum(:fetched_at/trading_date)`) are left uncached since stale sync timestamps would be misleading. |

## Portability (Railway → Render)

1. Create new Render services (web + worker + Postgres)
2. `pg_dump $DATABASE_URL > backup.sql`
3. `psql $NEW_DATABASE_URL < backup.sql`
4. Copy env vars from `.env.example`
5. Add Render cron entries matching the Railway schedule in README
6. Verify data integrity: `bin/rails runner "puts Stock.count; puts DailyPrice.count; puts Prediction.count"`
