# Architecture: finance-assist

## Service layer map

```
app/services/
├── market_data/
│   ├── provider.rb                        # Abstract interface (Phase 1)
│   ├── providers/
│   │   └── eodhd_client.rb                # EODHD API client (Phase 1)
│   └── importers/
│       ├── symbols_importer.rb            # PSE symbol list → stocks (Phase 1)
│       ├── eod_prices_importer.rb         # OHLCV → daily_prices (Phase 1)
│       ├── corporate_actions_importer.rb  # Dividends → corporate_actions (Phase 1)
│       └── fundamentals_importer.rb       # Financials → fundamentals (Phase 1)
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
│   ├── feature_builder.rb                 # TODO Phase 2: compute feature snapshots
│   └── scorer.rb                          # TODO Phase 2: weighted factor scoring
│
├── reporting/
│   ├── llm/
│   │   ├── client.rb                      # Abstract + factory (Phase 1)
│   │   ├── anthropic_client.rb            # Claude via Faraday + prompt caching (Phase 1)
│   │   └── openai_client.rb               # GPT-4o via Faraday (Phase 1)
│   └── report_generator.rb                # Templated stub → LLM upgrade in Phase 3
│
└── validation/
    ├── outcome_evaluator.rb               # TODO Phase 4: compute prediction_outcomes
    └── self_audit.rb                      # TODO Phase 4: compute self_audit_runs
```

## Data flow (Phase 1)

```
EODHD API
  → EodhdClient (raw JSON saved to data/raw/eodhd/ + raw_artifacts)
  → Importers (upsert → stocks, daily_prices, corporate_actions, fundamentals)

PSE EDGE
  → PseEdge::Fetcher (raw HTML/PDFs saved to data/raw/pse_edge/ + raw_artifacts)
  → ListingParser + DetailParser
  → PseEdge::Importer (upsert → disclosures; download attachments)

[Phase 2 — not yet implemented]
  DailyPrice + Disclosure → FeatureBuilder → feature_snapshots
  FeatureSnapshot → Scorer → predictions (immutable)

[Phase 3 — not yet implemented]
  Prediction + FeatureSnapshot → ReportGenerator (LLM) → prediction_reports

[Phase 4 — not yet implemented]
  Prediction + post-horizon DailyPrice → OutcomeEvaluator → prediction_outcomes
  PredictionOutcome → SelfAudit → self_audit_runs
```

## Key design decisions

| Decision | Rationale |
|----------|-----------|
| Provider abstraction for market data | EODHD (free tier) can be replaced by PSE FTP or paid vendor without changing importers |
| Predictions are immutable | Enables honest backtesting; old predictions cannot be retroactively improved |
| `raw_artifacts` table | Auditability — every API call and page fetch is traceable to a file on disk |
| PSE EDGE rate limit (2s floor, 50 req cap) | Respectful crawling; only pages already shown to users |
| solid_queue (Postgres-backed) | No Redis dependency; fits Railway free tier; portable to Render |
| LLM provider abstraction | Swap Claude ↔ GPT-4o via `LLM_PROVIDER` env var without code changes |
| Prompt caching on Anthropic system block | Reduces cost when the same system prompt is reused across multiple report generations |

## Portability (Railway → Render)

1. Create new Render services (web + worker + Postgres)
2. `pg_dump $DATABASE_URL > backup.sql`
3. `psql $NEW_DATABASE_URL < backup.sql`
4. Copy env vars from `.env.example`
5. Add Render cron entries matching the rake tasks in README
6. Verify data integrity: `bin/rails runner "puts Stock.count; puts DailyPrice.count"`
