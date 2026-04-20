---
name: plan-context
description: Load finance-assist project context before planning. TRIGGER proactively whenever the user asks for a plan, a design, an approach, or to "think about" a change in this repo (e.g. "let's plan X", "how should we approach Y", "design a solution for Z"), BEFORE entering plan mode or spawning Explore/Plan agents. Reads README.md, ARCHITECTURE.md, CLAUDE.md, and docs/handoff.md, and optionally uses the finance-assist MCP to sanity-check production data shape when the task touches predictions, reports, prices, disclosures, or audits.
---

# plan-context

Prime context before planning work in finance-assist. Doing this up front means the planning phase starts with the repo's architecture and conventions already loaded, so Explore/Plan agents and your own reasoning don't rediscover basics.

## When to run

Run this at the **start of a planning request**, before:
- Entering plan mode
- Spawning Explore or Plan sub-agents
- Drafting a plan file

Skip if the user's ask is a trivial one-liner (typo, rename, obvious bug fix) — the overhead isn't worth it.

## Steps

1. **Read the four context files in parallel** (single message, multiple Read calls):
   - `/home/alain/finance-assist/README.md`
   - `/home/alain/finance-assist/ARCHITECTURE.md`
   - `/home/alain/finance-assist/CLAUDE.md` (may already be in context — re-read only if not)
   - `/home/alain/finance-assist/docs/handoff.md`

2. **If the task touches live data shape** (predictions, reports, prices, disclosures, audits, pipeline status), call the relevant finance-assist MCP tool(s) to see what production actually looks like right now. Pick the minimum set:
   - Data freshness / record counts → `mcp__finance-assist__get_pipeline_status`
   - Prediction / report shape → `mcp__finance-assist__get_top_predictions` (limit 1–3)
   - Per-stock detail → `mcp__finance-assist__get_stock`
   - Audit / outcomes → `mcp__finance-assist__get_self_audit`
   - Disclosures → `mcp__finance-assist__search_disclosures`

   Skip the MCP step for pure-code refactors, infra/config changes, or UI-only work that doesn't depend on data shape.

3. **Do not summarize the docs back to the user.** Stay silent on the reading itself — just proceed into planning with the context loaded. A one-line "Loaded repo context." is fine if it helps pacing, but no bullet summaries.

4. **Then continue with the normal plan workflow**: explore specific code areas, design, write the plan file, ExitPlanMode.

## Notes

- The MCP tools are deferred — if their schemas aren't loaded yet, use `ToolSearch` with `select:mcp__finance-assist__<name>` first.
- Respect `CLAUDE.md` conventions (idempotency rules, etc.) when drafting the plan. They are project-level requirements, not suggestions.
- If a doc contradicts something you observe in the code, trust the code and flag the doc drift in the plan.
