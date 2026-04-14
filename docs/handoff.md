# Stock Research Assistant for Personal Use  
## Repo-specific handoff for `arfrancisco/finance-assist`

## 0. Repository context

Use this repository as the project home:

- Repository: `https://github.com/arfrancisco/finance-assist`

At the time of this handoff, the repository appears to be a **public empty repository**. That means the implementation should treat this as a greenfield setup inside an existing repo, not as an adaptation of an existing codebase.

Build the initial project structure directly in this repo.

---

## 1. Goal

Build a **personal-use stock research assistant** focused on **local stocks**, using periodically fetched market data plus supplementary information to help decide what stocks are worth reviewing for:

- short term
- medium term
- long term

This is **not** meant to be a fully autonomous trading bot or a magical prediction engine. The main purpose is:

- generate candidates to review
- rank stocks by horizon
- explain why they rank well
- track whether past recommendations were actually good
- improve the system over time through measured validation

The most important principle is:

**Use normal code and statistical logic for the actual ranking/prediction layer. Use LLMs mainly for coding help, summarization, reasoning over disclosures, and human-readable explanations.**

---

## 2. Constraints and assumptions

### Personal use
This is for personal use only, not a public/commercial product.

### Data collection model
The plan is to periodically fetch stock data and store it in a local database.

### Historical data caveat
Past stock data is often stable, but not always "final" in the sense that interpretation can change because of:

- stock splits
- dividends
- rights offerings
- ticker/company changes
- suspensions
- corrected disclosures
- adjusted-price series
- newly posted disclosures affecting historical understanding

So the system should store:

- raw fetched data
- normalized/processed data
- corporate actions and disclosures separately

### Initial provider decision
For v1, use **EOD Historical Data (EODHD)** as the market-data provider instead of the official PSE FTP product. The goal is to reduce setup friction and make integration easier while building the first version.

Assume:
- personal-use prototype
- EODHD free account for now
- low refresh frequency
- approximately 20 API calls per day available on the free tier
- PSE EDGE used only for disclosures and supplementary official filings

This means the architecture should separate:
- **market data provider layer** (EODHD for v1, swappable later)
- **official disclosures layer** (PSE EDGE)

### Important design mindset
The app should not simply say "buy this."
It should say something closer to:

- "Here are the top names to review"
- "Here is why they ranked highly"
- "Here are the risks"
- "Here is how this system has performed historically"

---

## 3. High-level product concept

A local stock research system that:

1. fetches end-of-day stock data on a schedule
2. ingests supplementary information such as disclosures and corporate actions
3. stores everything in a local DB
4. computes structured features and scores
5. ranks stocks for short/medium/long-term review
6. generates readable reports explaining the ranking
7. saves every prediction/report snapshot
8. validates those past predictions after the prediction window passes
9. produces self-audit metrics so I can quantify whether it is actually useful

---

## 4. What success looks like

The system is successful if it can do these things well:

- consistently narrow a large list of stocks into a smaller shortlist
- surface potentially interesting names I would not have noticed
- explain catalysts and risks clearly
- reduce emotional/random decision-making
- show measurable evidence of whether its recommendations are any good

This system does **not** need perfect accuracy.
It just needs to be useful and measurable.

---

## 5. Role of AI / models

## Claude
Use Claude primarily for:

- coding the provider clients and ingestion jobs
- implementing ETL jobs
- designing/refactoring the codebase
- helping with DB schema and app structure
- generating boilerplate and tests

## GPT / reasoning model
Use a stronger reasoning model for:

- analyzing disclosures
- summarizing news/corporate actions
- generating stock thesis summaries
- explaining why a stock ranks highly
- highlighting risks/catalysts
- comparing multiple candidates

## Smaller cheaper model
Use a cheaper model for repetitive support tasks:

- disclosure classification
- extracting structured fields
- basic summarization
- tagging catalysts/events
- sentiment bucketing

## Important note
The LLM should **not** be the main prediction engine.
The actual ranking should come from:

- rules
- factors
- statistics
- backtests
- explicit scoring logic
- optionally ML later

The LLM is mainly the explanation and research layer.

---

## 5A. Data sources and source-of-truth rules

For v1, use a hybrid source strategy:

### A. Market data provider: EODHD
Use **EOD Historical Data (EODHD)** as the primary source for:
- stock universe / ticker list
- historical end-of-day OHLCV
- dividends and splits if available
- company/fundamental/profile fields if available
- benchmark/index data if available through the provider

Why:
- easier integration than the official PSE FTP setup
- more stable than scraping quote pages
- enough for a personal-use prototype
- low-frequency pulls fit the free-tier call budget

Assumptions for v1:
- free account
- roughly 20 API calls per day
- avoid frequent refreshes
- prioritize batch-like daily updates over interactive re-fetching

### B. Official disclosures source: PSE EDGE
Use **PSE EDGE** as the official source for:
- company announcements
- financial reports
- other reports
- dividends and rights
- halts and suspensions
- exchange notices
- company information pages

Important:
- treat PSE EDGE as a conservative, low-frequency ingestion source
- do not build an aggressive crawler
- only fetch pages/documents intentionally exposed by the site
- prefer listing pages, detail pages, and linked attachments already presented to users
- keep request rates low and respectful

### Source-of-truth rules
- **Prices / volume / historical market series:** EODHD
- **Disclosures / filings / notices:** PSE EDGE
- **Corporate actions:** prefer EODHD if structured and available; cross-reference PSE EDGE where needed
- **Benchmark data:** EODHD initially
- **Local database becomes the internal source of truth after ingestion**

### Provider abstraction requirement
Implement the market-data ingestion behind a provider abstraction so EODHD can be replaced later by:
- official PSE FTP
- a paid licensed vendor
- another API provider

Suggested interface:
- fetch_symbols
- fetch_eod_prices(symbol, from_date, to_date)
- fetch_corporate_actions(symbol)
- fetch_fundamentals(symbol)
- fetch_index_data(symbol, from_date, to_date)

### Refresh cadence for v1
Given the free-tier budget and personal-use scope:

#### EODHD
- once daily after market close for latest prices
- one-time or occasional historical backfill jobs
- avoid repeated same-day fetches unless manually triggered

#### PSE EDGE
- once daily for new disclosures is enough for v1
- optionally twice daily on market days if still conservative
- weekly refresh for company master/company profile pages
- fetch attachments only when there is a new or relevant disclosure

### Raw artifact retention
Store raw source artifacts for auditability:
- original API response payloads from EODHD when practical
- original HTML references and URLs from PSE EDGE
- downloaded PDFs/attachments from PSE EDGE when used
- parsing timestamps
- source identifiers
- checksums where practical

---

## 6. Core system architecture

## A. Data ingestion layer

This layer periodically collects:

### Market data
- ticker / symbol
- trading date
- open
- high
- low
- close
- adjusted close if applicable
- volume
- value traded if available

### Supplementary data
- company disclosures
- corporate actions
- dividends
- rights offerings
- stock splits
- earnings announcements
- annual and quarterly reports
- sector/index context if available

### Ingestion notes
The ingestion layer should support two source types:

#### EODHD API ingestion
- API-key based fetches
- low-frequency scheduled pulls
- daily OHLCV updates
- occasional historical backfill
- provider abstraction so it can be swapped later

#### PSE EDGE disclosure ingestion
- conservative fetcher, not an aggressive crawler
- pull only from site pages/documents intentionally exposed to users
- start with listing pages and disclosure detail pages
- download linked PDF/report attachments only when relevant
- keep request volume low
- avoid unnecessary concurrency
- store source URL, fetch timestamp, and raw references

General requirements:
- run on a schedule
- avoid duplicate inserts
- store fetch timestamps
- store source URL / source metadata where practical
- keep raw response/snapshot when useful for debugging and auditing

---

## B. Storage layer

Use a local database first.

Recommended options:
- PostgreSQL for a stronger long-term setup
- SQLite for very simple local-only v1

Suggested tables:

### `stocks`
- id
- symbol
- company_name
- sector
- industry
- is_active
- created_at
- updated_at

### `daily_prices`
- id
- stock_id
- trading_date
- open
- high
- low
- close
- adjusted_close_nullable
- volume
- traded_value_nullable
- source
- fetched_at
- created_at

Unique key:
- stock_id + trading_date

### `disclosures`
- id
- stock_id
- disclosure_type
- title
- body_text
- disclosure_date
- source_url
- source_id_nullable
- fetched_at
- raw_payload_nullable
- created_at

### `corporate_actions`
- id
- stock_id
- action_type
- announced_date
- ex_date_nullable
- record_date_nullable
- payment_date_nullable
- description
- value_nullable
- source_url
- created_at

### `fundamentals`
- id
- stock_id
- period_type
- period_end_date
- revenue_nullable
- net_income_nullable
- eps_nullable
- book_value_nullable
- debt_nullable
- cash_nullable
- pe_nullable
- pb_nullable
- dividend_yield_nullable
- roe_nullable
- roa_nullable
- source
- fetched_at
- created_at

### `feature_snapshots`
- id
- stock_id
- as_of_date
- horizon
- momentum_5d_nullable
- momentum_20d_nullable
- momentum_60d_nullable
- volatility_20d_nullable
- avg_volume_20d_nullable
- relative_strength_nullable
- valuation_score_nullable
- quality_score_nullable
- liquidity_score_nullable
- catalyst_score_nullable
- risk_score_nullable
- total_score_nullable
- feature_version
- created_at

### `predictions`
- id
- stock_id
- as_of_date
- horizon
- recommendation_type
- rank_position_nullable
- predicted_probability_nullable
- predicted_direction_nullable
- expected_return_min_nullable
- expected_return_max_nullable
- confidence_nullable
- total_score
- benchmark_symbol_nullable
- model_version
- feature_version
- created_at

### `prediction_reports`
- id
- prediction_id
- summary_text
- catalyst_text
- risk_text
- rationale_text
- llm_model
- prompt_version
- created_at

### `prediction_outcomes`
- id
- prediction_id
- evaluation_date
- entry_price
- exit_price
- raw_return
- benchmark_entry
- benchmark_exit
- benchmark_return
- excess_return
- max_drawdown_nullable
- was_positive_nullable
- beat_benchmark_nullable
- outcome_label_nullable
- created_at

### `model_versions`
- id
- version_name
- description
- algorithm_type
- weights_json
- notes
- created_at

### `self_audit_runs`
- id
- run_date
- horizon
- sample_size
- hit_rate
- avg_return
- avg_excess_return
- brier_score_nullable
- calibration_notes_nullable
- summary_text
- created_at

---

## 7. Ranking and scoring logic

Start simple. Do not start with deep ML.

Create separate scoring logic per horizon.

## Short-term ranking
Focus more on:
- momentum
- unusual volume
- liquidity
- short-term price strength
- recent catalysts/disclosures
- volatility/risk control

Possible features:
- 5-day return
- 10-day return
- volume spike ratio
- average volume
- recent disclosure flag
- breakout/reversal indicator
- sector relative strength

## Medium-term ranking
Focus on:
- sustained trend
- improving fundamentals
- reasonable valuation
- recent positive developments
- sector strength
- absence of obvious red flags

Possible features:
- 1-month and 3-month momentum
- earnings growth trend
- valuation relative to peers
- debt/quality measures
- disclosure/catalyst score

## Long-term ranking
Focus on:
- earnings growth
- balance sheet strength
- profitability quality
- valuation
- dividends
- business consistency / disclosure quality

Possible features:
- 6-month / 12-month trend
- earnings consistency
- ROE / ROA
- leverage
- dividend consistency
- valuation score
- quality score

## Scoring approach
Start with weighted factor scoring:

`total_score = weighted sum of normalized feature scores`

Keep all weights explicit and versioned.

Store the exact weights used in `model_versions`.

---

## 8. Prediction output format

The system must generate **explicit predictions**, not vague text.

Examples:

### Short term
- probability of beating benchmark over next 5 or 10 trading days
- rank among all eligible stocks
- expected return range

### Medium term
- probability of positive return over next 1 to 3 months
- rank among eligible stocks
- thesis and risks

### Long term
- attractiveness rank for 6 to 12 months
- probability of beating benchmark over horizon
- thesis and invalidation conditions

Important:
Every generated recommendation must be saved and never overwritten.

---

## 9. Why saving predictions/reports is mandatory

To validate later, the system must preserve what it said **at the time**.

Therefore save:

### Prediction record
Structured and measurable:
- stock
- date
- horizon
- score
- probability
- confidence
- direction
- expected return band
- model version
- feature version

### Report snapshot
Human-readable:
- summary
- catalysts
- risks
- rationale

### Outcome record
After the horizon passes:
- actual return
- benchmark return
- excess return
- drawdown
- whether it was correct

This creates an immutable audit trail.

Rule:
- save every recommendation
- never edit historical predictions
- create new rows on new runs

---

## 10. Validation framework

Since the user has limited personal investing knowledge, the app must prove itself with metrics.

### Define correctness clearly
Examples:

- short term: beat benchmark over next 5 trading days
- medium term: positive return over next 1 month or beat benchmark over next 3 months
- long term: positive excess return over 6 or 12 months

### Compare to baselines
Possible baselines:
- buy the index
- equal-weight top liquid names
- buy last period's winners
- random selection from liquid stocks
- simple momentum-only strategy

### Use rolling time-based validation
Never use random train/test splitting.

Validation should happen chronologically:
1. build model on past data
2. generate predictions for a future period
3. save them
4. wait for outcomes
5. score them
6. roll forward and repeat

### Metrics to track
- average return of top 3 / top 5 picks
- average excess return vs benchmark
- spread between top-ranked and bottom-ranked names
- hit rate
- accuracy
- precision
- recall
- F1
- Brier score
- calibration by confidence band

### Self-audit
Because the system keeps fetching data and generating predictions, it can continuously evaluate itself.

Suggested cadence:
- weekly
- monthly
- quarterly

Do not let it automatically rewrite its own ranking logic without review.

---

## 11. Practical v1 scope

## V1 objective
A working personal stock research assistant that:

- fetches market data from EODHD
- ingests disclosures from PSE EDGE conservatively
- stores both locally
- computes factor scores
- ranks stocks for 3 horizons
- writes readable reports
- logs every recommendation
- scores those recommendations later
- shows historical performance vs benchmark

## V1 non-goals
- real-time trading
- fully autonomous strategy execution
- advanced deep learning
- perfect price prediction
- automated portfolio management
- public/commercial scale

---

## 12. Suggested v1 workflow

### Daily / scheduled jobs
1. fetch latest daily stock prices from EODHD
2. fetch new disclosures from PSE EDGE using a conservative low-frequency collector
3. fetch or update corporate actions/fundamentals from EODHD if available
4. normalize and store data
5. compute/update derived features
6. generate latest rankings by horizon
7. generate LLM summaries for top candidates
8. save prediction rows and report snapshots

### Outcome evaluation job
1. find predictions whose horizon window has completed
2. compute realized performance
3. compare against benchmark
4. store results in `prediction_outcomes`

### Weekly self-audit job
1. aggregate recent outcomes
2. compute metrics by horizon
3. compare against baselines
4. generate a self-audit summary
5. flag potential scoring issues

---

## 13. Recommended project structure for this repo

Since the repo is currently empty, scaffold it intentionally.

Suggested initial structure:

```text
finance-assist/
  README.md
  .env.example
  Gemfile
  config/
  db/
    migrate/
    schema.rb
    seeds.rb
  app/
    models/
    services/
      market_data/
        providers/
          eodhd_client.rb
        importers/
      disclosures/
        pse_edge/
      ranking/
      validation/
      reporting/
    jobs/
  lib/
  spec/
  data/
    raw/
      eodhd/
      pse_edge/
    processed/
  scripts/
```

If using Rails, organize these under standard Rails conventions.

Core service areas:
- `MarketData::Providers::EodhdClient`
- `MarketData::Importers::*`
- `Disclosures::PseEdge::*`
- `Ranking::*`
- `Validation::*`
- `Reporting::*`

---


## 13A. Deployment and portability requirements

Start with **Railway** for v1 because it is likely the cheapest and easiest place to run this personal-use app. However, the app must remain portable so it can later be moved to **Render** without major rework or data loss.

### Portability requirements
- keep the app platform-neutral
- use standard PostgreSQL as the main database
- keep configuration in environment variables
- avoid platform-specific app logic
- ensure all scheduled jobs can also be run manually from CLI commands or rake tasks
- keep file/data storage organized so raw artifacts can be backed up and moved

### Database portability
The system should assume the database may later be migrated using standard PostgreSQL tools such as:
- `pg_dump`
- `pg_restore`

Do not rely on database features that would make a standard Postgres export/import difficult.

### Scheduled job portability
Scheduled jobs must be defined as normal application commands, for example:
- daily EODHD sync command
- daily PSE EDGE sync command
- outcome evaluation command
- weekly self-audit command

Railway or Render cron/scheduler configuration should only trigger these commands. The business logic itself must not live only in platform scheduler settings.

### File and raw-data portability
If raw artifacts are stored locally, keep them in a predictable folder structure and document them clearly. If the project later outgrows local disk storage, it should be easy to move to object storage without changing the rest of the system design.

### Migration expectation
A later Railway-to-Render migration should be treated as:
1. create new Render services
2. export Postgres data from Railway
3. import Postgres data into Render
4. point environment variables and scheduled jobs to the new deployment
5. verify data integrity and app behavior

The implementation should make that process straightforward.

---

## 14. Recommended development order

## Phase 1: foundation
- initialize the app in this repo
- create DB schema
- build stock universe table
- build EODHD provider client
- build PSE EDGE disclosure collector
- store raw + normalized data

## Phase 2: feature engineering
- implement basic momentum features
- implement liquidity and volatility features
- implement disclosure/catalyst flags
- create scoring functions for short/medium/long horizons

## Phase 3: recommendation engine
- generate ranked lists
- save predictions
- generate human-readable reports
- save report snapshots

## Phase 4: evaluation
- build outcome calculator
- compute returns vs benchmark
- build validation metrics
- generate self-audit summaries

## Phase 5: refinement
- adjust factor weights
- improve disclosure extraction
- compare against simple baselines
- maybe test lightweight ML later

---

## 15. Direct build brief for Claude

Use this repository: `https://github.com/arfrancisco/finance-assist`

The repository currently appears empty, so scaffold the initial application in that repo.

Build a personal-use local stock research assistant for local stocks. For v1, use **EOD Historical Data (EODHD)** as the market-data provider and assume a free-tier account with a limited daily API-call budget, so the system should use low-frequency scheduled fetches rather than frequent polling. Use **PSE EDGE** as the official disclosures source, but ingest it conservatively by fetching only site pages and linked documents intentionally exposed to users, with low request volume and no aggressive crawling. Store market data, disclosures, and related source metadata in a local database.

The system should compute structured features, rank stocks for short-, medium-, and long-term review, and generate human-readable reports explaining the ranking. The core ranking logic should be based on explicit factor scoring and statistical logic, not solely on LLM judgment. LLMs should mainly be used for coding help, summarization, catalyst/risk extraction, and human-readable explanations.

The system must save every prediction and report snapshot as an immutable historical record so that later, after the horizon passes, it can validate itself against actual outcomes. It must also compute rolling evaluation metrics such as hit rate, average return, excess return vs benchmark, and confidence calibration. Build this in a way that avoids look-ahead bias and supports model versioning, prediction logging, periodic self-audit summaries, and a provider abstraction so EODHD can be replaced later. Start with a practical v1 scope and clear schema design rather than over-optimizing early.
