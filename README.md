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
- solid_queue (background jobs, Postgres-backed)
- Faraday (HTTP client)
- Nokogiri (HTML parsing)
- RSpec + VCR (testing)

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
# Fill in EODHD_API_KEY, ANTHROPIC_API_KEY or OPENAI_API_KEY, DATABASE_URL
```

### 3. Set up the database

```bash
bin/rails db:create db:migrate db:seed
```

### 4. Run the test suite

```bash
bin/rspec
```

---

## Daily ingest jobs

All jobs can be run manually via rake tasks or triggered by Railway/Render cron.

```bash
# Refresh the stock universe from EODHD (run weekly)
bin/rails finance:refresh_symbols

# Fetch latest EOD prices for all active stocks (run daily after market close)
bin/rails finance:ingest_eodhd

# Backfill historical prices for a single symbol
bin/rails finance:backfill_prices SYMBOL=ALI FROM=2020-01-01 TO=2024-12-31

# Fetch latest PSE EDGE disclosures (run daily)
bin/rails finance:ingest_pse_edge

# Evaluate past predictions whose horizon has elapsed (run daily)
bin/rails finance:evaluate_outcomes

# Generate weekly self-audit summary
bin/rails finance:self_audit
```

---

## Running the worker

```bash
bin/jobs start
```

---

## Railway deployment

### Cron entries (Railway scheduler)

| Schedule           | Command                               |
|--------------------|---------------------------------------|
| `0 10 * * 1-5`     | `bin/rails finance:ingest_eodhd`      |
| `0 11 * * 1-5`     | `bin/rails finance:ingest_pse_edge`   |
| `0 12 * * 1-5`     | `bin/rails finance:evaluate_outcomes` |
| `0 8 * * 1`        | `bin/rails finance:refresh_symbols`   |
| `0 9 * * 1`        | `bin/rails finance:self_audit`        |

### Procfile processes

- `web`: Rails server
- `worker`: solid_queue job worker

---

## Portability (Railway → Render)

The app uses only standard PostgreSQL. To migrate to Render:

1. Create new Render services (web + worker + Postgres)
2. Export: `pg_dump $DATABASE_URL > backup.sql`
3. Import: `psql $NEW_DATABASE_URL < backup.sql`
4. Set env vars from `.env.example`
5. Point Railway cron commands at new deployment

---

## Data directory

Raw API responses and HTML pages are stored under `data/raw/` for auditability.
This directory is gitignored. Back it up separately if needed.

```
data/
  raw/
    eodhd/        # Raw JSON from EODHD API calls
    pse_edge/     # Raw HTML from PSE EDGE pages + downloaded PDFs
  processed/      # Derived/transformed data artifacts
```

---

## End-to-end smoke test (Phase 1)

Run these in order after a fresh clone to verify the full Phase 1 pipeline:

```bash
# 1. Install and set up
bundle install
cp .env.example .env   # fill in EODHD_API_KEY, ANTHROPIC_API_KEY or OPENAI_API_KEY

# 2. Database
PGPASSWORD=postgres PGUSER=postgres PGHOST=localhost \
  bin/rails db:create db:migrate db:seed
# Expected: 12 migrations applied; model_versions seeded with 1 record

# 3. Refresh stock universe from EODHD
EODHD_API_KEY=<your_key> bin/rails finance:refresh_symbols
# Expected: stocks table populated with PSE symbols; raw JSON in data/raw/eodhd/

# 4. Backfill one symbol to verify price ingestion
EODHD_API_KEY=<your_key> bin/rails finance:backfill_prices SYMBOL=ALI FROM=2024-01-01 TO=2024-12-31
# Expected: daily_prices rows for ALI; raw_artifacts records created; idempotent on re-run

# 5. Daily price ingest (all active stocks)
EODHD_API_KEY=<your_key> bin/rails finance:ingest_eodhd
# Expected: latest trading day prices added; re-running is idempotent

# 6. PSE EDGE disclosure ingest
bin/rails finance:ingest_pse_edge
# Expected: disclosures rows created; raw HTML on disk under data/raw/pse_edge/
#           request rate-limit (2s floor) visible in Rails log

# 7. Full test suite
bin/rspec
# Expected: 59 examples, 0 failures
```

---

## Architecture phases

| Phase | Scope |
|-------|-------|
| 1 | Foundation: ingest, storage, CLI jobs *(complete)* |
| 2 | Feature engineering: momentum, volatility, liquidity, factor scores |
| 3 | Ranking + LLM reports: top-N selection, prediction snapshots |
| 4 | Validation: outcome evaluation, self-audit metrics |
| 5 | Refinement: weight tuning, baselines, optional ML |

---

## Phase 2 entry points (next steps)

When starting Phase 2, these are the files to fill in:

| File | Purpose |
|------|---------|
| [app/services/ranking/feature_builder.rb](app/services/ranking/feature_builder.rb) | Compute momentum, volatility, liquidity, catalyst scores from `daily_prices` and `disclosures` |
| [app/services/ranking/scorer.rb](app/services/ranking/scorer.rb) | Apply `model_versions.weights_json` to feature snapshots to produce `total_score` |
| [app/services/validation/outcome_evaluator.rb](app/services/validation/outcome_evaluator.rb) | Join post-horizon prices to predictions; populate `prediction_outcomes` |
| [app/services/validation/self_audit.rb](app/services/validation/self_audit.rb) | Aggregate outcomes into `self_audit_runs`; compute hit rate, Brier score, etc. |

Phase 3 then replaces the templated `PredictionReport` text with real LLM calls via
`Reporting::Llm::Client.build` — the interface is already wired in
[app/services/reporting/report_generator.rb](app/services/reporting/report_generator.rb).
