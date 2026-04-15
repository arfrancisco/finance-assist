# CLAUDE.md — finance-assist

Developer conventions for this codebase. See ARCHITECTURE.md for the full service map.

## Jobs & Idempotency

**All jobs must be idempotent** — safe to rerun without creating duplicates or corrupting data. This is a hard requirement so jobs can be safely retried on failure or triggered manually.

### Required patterns

1. **Prefer `upsert` / `upsert_all` over `create!`** for any record with a natural business key.
2. **Add a DB unique constraint** on the natural key — an application-level `exists?` check alone is not enough (race conditions under concurrency).
3. **`exists?` guards are secondary only** — use them to skip unnecessary work, but never as the sole safeguard against duplicates.
4. **If `create!` is truly unavoidable** (e.g., append-only log with no natural key), document explicitly in a comment why idempotency is not achievable.

### Current job idempotency map

| Job / Service | Writes to | Unique key | Pattern |
|---|---|---|---|
| `EodPricesImporter#call` / `#call_all` | `daily_prices` | `(stock_id, trading_date)` | `upsert_all` |
| `SymbolsImporter#call` | `stocks` | `symbol` | `upsert_all` |
| `PseEdge::Importer#call` | `disclosures` | `source_id` | `exists?` guard + `create!` |
| `FeatureBuilder#call` | `feature_snapshots` | `(stock_id, as_of_date, horizon)` | `upsert` |
| `Scorer#persist_prediction` | `predictions` | `(stock_id, as_of_date, horizon, model_version_id)` | `upsert` |
| `ReportGenerator#call` | `prediction_reports` | `prediction_id` | `exists?` guard + `create!` (DB unique constraint) |
| `OutcomeEvaluator#call` | `prediction_outcomes` | `prediction_id` | left-join guard + `create!` (DB unique constraint) |
| `SelfAudit#call` | `self_audit_runs` | `(run_date, horizon)` | `upsert` |
| `IngestPseIndexJob#perform` | `daily_prices` | `(stock_id, trading_date)` | `upsert_all` |

### Adding a new job

When writing a new job or service that writes to the database:

1. Identify the natural business key (what makes a row unique semantically).
2. Add a DB-level unique index on that key in a migration.
3. Use `upsert` / `upsert_all` with `unique_by:` pointing to that key.
4. Add an idempotency comment at the top of the `call` method:
   ```ruby
   # Idempotent on (col_a, col_b) via upsert
   def call
   ```
