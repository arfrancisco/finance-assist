# finance-assist

A personal-use stock research assistant for local (PSE) stocks.

Fetches end-of-day market data from EODHD, ingests disclosures from PSE EDGE,
computes factor scores, ranks stocks by investment horizon, generates LLM-backed
research reports, and tracks the accuracy of past recommendations over time.

**Not a trading bot.** The system surfaces candidates to review and explains why
they ranked highly — it does not execute trades or give financial advice.

---

## Stack

- Ruby 3.4 / Rails 7.1
- PostgreSQL
- solid_queue (background jobs, Postgres-backed — no Redis)
- Faraday + faraday-retry (HTTP client)
- Nokogiri (HTML parsing)
- Tailwind CSS (via tailwindcss-rails)
- Hotwire (Turbo + Stimulus)
- RSpec + VCR + WebMock (testing)

---

## Quickstart

### 1. Clone and install

```bash
git clone https://github.com/arfrancisco/finance-assist
cd finance-assist
bundle install
```

### 2. Configure environment

```bash
cp .env.example .env
# Fill in at minimum: EODHD_API_KEY, DATABASE_URL
# For LLM reports (Phase 3): ANTHROPIC_API_KEY or OPENAI_API_KEY
```

### 3. Set up the database

```bash
bin/rails db:create db:migrate db:seed
# Seeds: model_versions v0-placeholder and v1 (Phase 2 factor weights)
```

### 4. Start the development server

```bash
bin/dev   # starts Rails + Tailwind CSS watcher via Procfile.dev
```

Visit `http://localhost:3000` to see the ingestion inspector UI.

### 5. Run the test suite

```bash
bin/rspec
```

---

## Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection URL |
| `EODHD_API_KEY` | Yes | EODHD API key for market data |
| `LLM_PROVIDER` | Phase 3+ | `anthropic` or `openai` (default: `anthropic`) |
| `ANTHROPIC_API_KEY` | Phase 3+ | Claude API key (if using Anthropic) |
| `OPENAI_API_KEY` | Phase 3+ | OpenAI API key (if using OpenAI) |
| `PSE_EDGE_USER_AGENT` | No | Defaults to `finance-assist-personal/1.0` |
| `RAW_DATA_DIR` | No | Defaults to `data/raw` |
| `RAILS_MAX_THREADS` | No | Puma thread count, defaults to 5 |

---

## Rake tasks

All tasks can be run manually or triggered by cron.

### Data ingestion

```bash
# Refresh the PSE stock universe from EODHD (run weekly)
bin/rails finance:refresh_symbols

# Fetch latest EOD prices for all active stocks via bulk endpoint (run daily after market close)
bin/rails finance:ingest_eodhd
bin/rails finance:ingest_eodhd DATE=2024-12-31   # fetch bulk prices for a specific date

# Backfill historical prices for a single symbol (uses per-symbol endpoint)
bin/rails finance:backfill_prices SYMBOL=ALI FROM=2020-01-01 TO=2024-12-31

# Fetch latest PSE EDGE disclosures (run daily)
bin/rails finance:ingest_pse_edge
bin/rails finance:ingest_pse_edge PAGES=5   # fetch more listing pages
```

### Ranking (Phase 2)

```bash
# Compute feature snapshots for all active stocks
bin/rails finance:compute_features                        # defaults to yesterday
bin/rails finance:compute_features DATE=2024-12-31
bin/rails finance:compute_features DATE=2024-12-31 SYMBOL=ALI   # single stock

# Score predictions from feature snapshots
bin/rails finance:score_predictions                       # defaults to yesterday, model v1
bin/rails finance:score_predictions DATE=2024-12-31
bin/rails finance:score_predictions DATE=2024-12-31 MODEL=v1
```

### LLM Reports (Phase 3)

```bash
# Generate research reports for top-ranked predictions
bin/rails finance:generate_reports                              # defaults to yesterday, all horizons, top 10
bin/rails finance:generate_reports DATE=2024-12-31
bin/rails finance:generate_reports DATE=2024-12-31 HORIZON=5d TOP=5
```

### Validation (Phase 4)

```bash
# Evaluate predictions whose horizon has elapsed (run daily)
bin/rails finance:evaluate_outcomes

# Generate weekly self-audit summary
bin/rails finance:self_audit
```

### Weight retuning (Phase 5)

```bash
# Suggest new weights from outcome correlations (run manually when you have enough outcomes)
bin/rails finance:retune_weights              # defaults to MODEL=v1
bin/rails finance:retune_weights MODEL=v1

# Then use the new weights for scoring
bin/rails finance:score_predictions MODEL=v2
```

---

## Running the worker

```bash
bundle exec rake solid_queue:start
```

---

## Railway deployment

### Procfile processes

| Process | Command |
|---------|---------|
| `web` | `bundle exec rails server` |
| `worker` | `bundle exec rake solid_queue:start` |
| `release` | `bundle exec rails db:migrate db:seed` |

### Recommended cron schedule (Railway cron services)

| Schedule (UTC) | Command | Notes |
|----------------|---------|-------|
| `0 0 * * 1` | `bundle exec rails finance:refresh_symbols` | Weekly, Mon midnight UTC |
| `0 5 * * 1-5` | `bundle exec rails finance:ingest_eodhd` | Daily after PSE close (1pm PHT = 5am UTC) |
| `0 5 * * 1-5` | `bundle exec rails finance:ingest_pse_edge` | Same time as EODHD |
| `0 6 * * 1-5` | `bundle exec rails finance:compute_features` | After ingest |
| `0 7 * * 1-5` | `bundle exec rails finance:score_predictions` | After features |
| `0 8 * * 1-5` | `bundle exec rails finance:generate_reports` | After scoring (Phase 3) |
| `0 9 * * 1-5` | `bundle exec rails finance:evaluate_outcomes` | After reports (Phase 4) |
| `0 10 * * 1` | `bundle exec rails finance:self_audit` | Weekly Monday (Phase 4) |

---

## Data directory

Raw API responses and HTML pages are stored under `data/raw/` for auditability.
This directory is gitignored. Back it up separately if needed.

```
data/
  raw/
    eodhd/        # Raw JSON from EODHD API calls
    pse_edge/     # Raw HTML from PSE EDGE pages + downloaded PDFs
```

---

## Architecture overview

```
EODHD API
  → EodhdClient (bulk endpoint — 1 API call for full exchange)
  → EodPricesImporter → daily_prices

PSE EDGE
  → PseEdge::Fetcher (rate-limited: 2s floor, 50 req/run cap)
  → ListingParser + DetailParser
  → PseEdge::Importer → disclosures

daily_prices + disclosures + fundamentals
  → FeatureBuilder → feature_snapshots (per stock × per horizon)
  → Scorer (z-score normalization + weighted factors) → predictions (immutable)

predictions + feature snapshots + disclosures
  → ReportGenerator (structured LLM prompt, Anthropic prompt cached) → prediction_reports

[Phase 4] predictions + post-horizon prices → OutcomeEvaluator → prediction_outcomes
          prediction_outcomes → SelfAudit → self_audit_runs
[Phase 5] outcomes × features → WeightTuner → new ModelVersion (advisory)
```

### Key design decisions

| Decision | Rationale |
|----------|-----------|
| Predictions are immutable | Enables honest backtesting — old predictions can't be retroactively improved |
| Bulk EODHD endpoint | 1 API call for full PSE exchange vs. 1 per symbol — respects free tier |
| PSE EDGE rate limit (2s floor, 50 req cap) | Respectful crawling of a public exchange site |
| `raw_artifacts` table | Every API call and page fetch is traceable |
| solid_queue (Postgres-backed) | No Redis dependency; fits Railway/Render free tier |
| LLM provider abstraction | Swap Claude ↔ GPT-4o via `LLM_PROVIDER` env var without code changes |
| Z-score normalization in Scorer | Cross-stock feature comparison is scale-independent |
| Per-horizon factor weights | 5d/20d/60d horizons weight momentum vs. value differently |

---

## Phases

| Phase | Status | Scope |
|-------|--------|-------|
| 1 | ✅ Complete | Scaffold, DB schema, EODHD client, PSE EDGE collector, CLI jobs |
| 2 | ✅ Complete | Feature engineering (momentum, volatility, RS), factor scoring, ranked predictions |
| 3 | ✅ Complete | Structured LLM prompt → prediction_reports (Claude/GPT-4o, prompt cached) |
| 4 | ✅ Complete | OutcomeEvaluator (entry/exit vs PSEi), SelfAudit (hit rate, Brier score) |
| 5 | ✅ Complete | WeightTuner — correlation-based weight retuning → new ModelVersion |
| UI | 🔄 In progress | Ingestion inspector (Status, Stocks, Prices, Disclosures); Features/Predictions/Reports planned |

---

## Frontend (Ingestion Inspector)

A simple read-only internal UI for verifying that the pipeline is working.

| Route | Description |
|-------|-------------|
| `/` | System status — last sync times, record counts |
| `/stocks` | Active stocks with latest price date, row counts |
| `/stocks/:id` | Stock detail — prices, disclosures, snapshots, predictions |
| `/daily_prices` | Price browser with symbol + date range filters |
| `/disclosures` | Disclosure browser with symbol filter |

Run with `bin/dev` in development (starts Rails + Tailwind CSS watcher).

---

## Portability (Railway → Render)

The app uses only standard PostgreSQL — no Redis, no proprietary services.

1. Create new Render services (web + worker + Postgres)
2. Export: `pg_dump $DATABASE_URL > backup.sql`
3. Import: `psql $NEW_DATABASE_URL < backup.sql`
4. Copy env vars from `.env.example`
5. Add Render cron entries matching the Railway schedule above
6. Verify: `bin/rails runner "puts Stock.count; puts DailyPrice.count; puts Prediction.count"`

---

## End-to-end smoke test

Run in order after a fresh clone:

```bash
# 1. Setup
bundle install
cp .env.example .env   # fill in EODHD_API_KEY

# 2. Database
bin/rails db:create db:migrate db:seed
# Expected: migrations applied; v0-placeholder and v1 model_versions seeded

# 3. Stock universe
bin/rails finance:refresh_symbols
# Expected: stocks table populated; raw JSON in data/raw/eodhd/symbols/

# 4. Backfill one symbol
bin/rails finance:backfill_prices SYMBOL=ALI FROM=2024-01-01 TO=2024-12-31
# Expected: daily_prices rows for ALI; raw_artifacts records; idempotent on re-run

# 5. Daily price ingest (bulk — 1 API call)
bin/rails finance:ingest_eodhd
# Expected: latest trading day prices added for all stocks

# 6. Disclosure ingest
bin/rails finance:ingest_pse_edge
# Expected: disclosures created; raw HTML on disk; 2s rate limit visible in logs

# 7. Feature computation
bin/rails finance:compute_features DATE=2024-12-31
# Expected: feature_snapshots rows for 3 horizons × all stocks with sufficient data

# 8. Score predictions
bin/rails finance:score_predictions DATE=2024-12-31
# Expected: predictions created; top 10 per horizon printed to stdout

# 9. Generate LLM reports (requires ANTHROPIC_API_KEY or OPENAI_API_KEY)
bin/rails finance:generate_reports DATE=2024-12-31 HORIZON=5d TOP=3
# Expected: 3 prediction_reports rows; LLM model and prompt_version recorded

# 10. Verify reports
bin/rails runner "pp PredictionReport.last.slice(:summary_text, :llm_model, :prompt_version)"
# Expected: summary_text populated, llm_model = 'claude-opus-4-6' (or gpt-4o), prompt_version = 'v1-llm'

# 11. Evaluate outcomes (needs predictions older than horizon window — skip on fresh data)
bin/rails finance:evaluate_outcomes
# Expected: 0 evaluated (no elapsed predictions on fresh data); safe to re-run

# 12. Self-audit (needs evaluated outcomes — skip on fresh data)
bin/rails finance:self_audit
# Expected: 0 runs created (not enough data); safe to re-run

# 13. Full test suite
bin/rspec
# Expected: 117 examples, 0 failures
```
