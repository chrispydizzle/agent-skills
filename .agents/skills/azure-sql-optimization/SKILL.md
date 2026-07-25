---
name: azure-sql-optimization
description: |
  Query performance optimization for Azure SQL Database and Azure SQL Managed Instance. Use when diagnosing slow queries, plan regressions, high CPU/DTU, blocking, missing indexes, or tempdb spills; when reading execution plans; or when applying Query Store, Intelligent Query Processing (IQP), or automatic tuning. Focuses on Azure SQL-specific
  tooling, not generic cross-database advice.
  Triggers: "optimize Azure SQL query", "slow query in Azure SQL", "Azure SQL performance",
  "Query Store", "execution plan", "missing index", "parameter sniffing", "tune T-SQL",
  "Managed Instance performance", "high DTU".
---

# Azure SQL Query Optimization

Diagnose and fix slow queries on **Azure SQL Database** and **Azure SQL Managed
Instance**. This skill emphasizes the platform's built-in tooling — **Query Store**
(on by default), **automatic tuning**, and **Intelligent Query Processing** — and a
*measure-first*, *least-invasive-fix-first* methodology. It is not a generic
cross-engine guide; for MySQL/PostgreSQL/Oracle use a general SQL skill instead.

## Methodology (always follow this loop)

1. **Confirm it's the query, not the tier.** Check resource health first — if the
   database is pinned at the CPU/IO limit of its service tier, optimization may be
   moot or you may be tuning the wrong thing. (`dmvs.md` → resource health.)
2. **Find the expensive statement.** Rank by total CPU / logical reads / duration
   using **Query Store** (historical) or DMVs (live). Don't guess.
3. **Get the actual execution plan.** Tune from *actual* row counts, never estimates
   alone. (`execution-plans.md`.)
4. **Diagnose the root cause.** Estimated-vs-actual skew, scans where seeks are
   expected, key lookups, spills, implicit conversions, bad sniffed plans.
5. **Apply the least-invasive fix that works** (see the fix ladder below). Re-measure
   the same way you measured in step 2.
6. **Verify and let the platform hold the line** — keep FORCE_LAST_GOOD_PLAN on;
   force a good plan or apply a Query Store hint if needed.

## Offer to run it — surface what you can do

Don't stop at theory. This skill can *do the work against the user's database*, not just
advise. When a task involves a specific query or proc, or a "why is my DB slow" question,
**lead with a short menu of what you can run**, then actually run whichever the user wants
and report measured results. Ask for a connection (or a non-prod copy / the actual plan)
*early* — don't wait to be handed access.

What you can offer to run (each detailed in the references):

- **Benchmark a change** — actual plan + `SET STATISTICS IO, TIME` before/after, the
  before/after matrix for a hot proc, and a no-regression control. (`execution-plans.md`)
- **Query Store triage** — rank the worst CPU/IO/duration queries and surface the plan
  **regression** shortlist (`plan_count > 1`). (`query-store.md`)
- **Index audit** — harvest missing-index *and* unused/write-heavy indexes and return a
  **consolidated, validated** change-set (no near-duplicates). (`dmvs.md`, `indexing.md`)
- **IQP / compat-level readiness** — report the current compat level and which IQP
  features it leaves unused, with a gated upgrade plan. (`iqp.md`)
- **Statistics freshness audit** — find stale stats (high modification counter) and
  refresh the ones that matter. (`dmvs.md`, `indexing.md`)
- **Anti-pattern scan** — given a proc or its actual plan, flag non-SARGable predicates,
  implicit conversions, scalar UDFs, `SELECT *`, OR-across-columns, deep OFFSET, NOLOCK,
  with fixes. (`antipatterns.md`)
- **Tier-vs-query verdict / live blocking** — pull resource stats and the live blocking
  chain to separate an undersized tier from a slow query. (`dmvs.md`)
- **Validate before declaring victory** — verify rewrites are byte-identical and run a
  **write-path / deadlock stress** check before shipping an index/indexed-view change.
  (`getquestionlistv2-case-study.md`)

If a SQL connection or SQL MCP/tool is available, **use it to measure** rather than
reasoning from theory. Measured results beat plausible-sounding advice.

## First-response triage

Run these first; for step (1), use the resource-health query that matches your platform. Each links to deeper queries in the references.

```sql
-- 1) Are we hitting the service-tier ceiling? (Azure SQL Database)
SELECT TOP (4) end_time, avg_cpu_percent, avg_data_io_percent, avg_log_write_percent
FROM sys.dm_db_resource_stats ORDER BY end_time DESC;

-- 2) What's the worst query right now?
SELECT TOP (5) r.session_id, r.status, r.wait_type, r.blocking_session_id,
       r.cpu_time, r.logical_reads,
       SUBSTRING(t.text,(r.statement_start_offset/2)+1,200) AS stmt
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID ORDER BY r.cpu_time DESC;

-- 3) Top historical CPU burners (Query Store is enabled by default)
--    Full query in references/query-store.md
```

If `blocking_session_id` is non-zero, you have a **blocking** problem (chase the
chain in `dmvs.md`), not a plan problem.

## Symptom → cause → reference

| Symptom | Likely cause | Start here |
|---------|--------------|-----------|
| Same query sometimes fast, sometimes slow | Parameter sniffing / plan regression | `query-store.md`, `antipatterns.md` |
| Plan shows a **Scan** where you expected a **Seek** | Missing/wrong index or non-SARGable predicate | `indexing.md`, `antipatterns.md` |
| **Key Lookup** per row | Non-covering index | `indexing.md` |
| Implicit-conversion warning on an operator | Type mismatch (often NVARCHAR vs VARCHAR) | `antipatterns.md` |
| Sort/Hash **spill to tempdb**, `RESOURCE_SEMAPHORE` waits | Bad memory grant / estimate | `iqp.md` (memory grant feedback), `execution-plans.md` |
| Slow UDF-heavy reporting query | Scalar UDF per-row execution | `iqp.md` (UDF inlining), `antipatterns.md` |
| High CPU on analytic aggregates/scans | Row-mode execution, no columnstore | `indexing.md` (columnstore), `iqp.md` (batch mode) |
| Queries blocking each other | Long transactions / lock contention | `dmvs.md` |
| Deep pagination gets slower by page | `OFFSET` pagination | `antipatterns.md` (keyset) |
| Hot proc sorts a whole partition before `TOP/OFFSET` | Missing preordered access path / offset-bound dynamic SQL | `getquestionlistv2-case-study.md`, `indexing.md` |
| Indexed-view read win creates write deadlocks | Over-broad schemabound view maintenance on hot rows | `getquestionlistv2-case-study.md` |
| Hitting CPU/DTU ceiling constantly | Workload exceeds tier | `dmvs.md` (resource health) |

## The fix ladder (prefer the top rung that solves it)

Apply the **least-invasive** fix first. Azure SQL uniquely lets you fix many issues
**without changing application code**.

1. **Statistics / index** — update stale stats; add a covering or filtered index;
   consolidate missing-index suggestions. (`indexing.md`, `dmvs.md`)
2. **Compatibility level + IQP** — raising to 170 unlocks PSP optimization, CE/DOP
   feedback, memory grant feedback, batch mode, UDF inlining. Test with Query Store.
   (`iqp.md`)
3. **Query Store — force plan / Query Store hint** — pin a good plan or inject a hint
   (`RECOMPILE`, `MAXDOP`, `OPTIMIZE FOR`) by `query_id`, no redeploy. (`query-store.md`)
4. **Automatic tuning** — let the platform create/drop indexes (DB only) and
   auto-correct regressed plans, with validation and auto-revert. (`automatic-tuning.md`)
5. **Query rewrite** — make predicates SARGable, eliminate scalar UDFs/MSTVFs, go
   set-based, project explicit columns. (`antipatterns.md`)
6. **Schema / service tier** — partitioning, columnstore, or scaling the tier when
   the workload genuinely exceeds resources. (`indexing.md`, `dmvs.md`)

## Azure SQL toolbox at a glance

- **Query Store** — on by default; the flight recorder for plans, runtime stats, and
  waits. Survives restarts/failovers. Force plans and apply hints from here.
- **Automatic tuning** — FORCE_LAST_GOOD_PLAN (DB + MI), CREATE/DROP INDEX (DB only),
  with automatic validation and rollback.
- **Intelligent Query Processing** — optimizer/runtime features gated by
  compatibility level; large gains with little/no code change.
- **DMVs** — live state, blocking, waits, missing/unused indexes, resource health.
- **READ_COMMITTED_SNAPSHOT is ON by default** in Azure SQL Database — readers don't
  block writers; don't reach for `NOLOCK`.

## Reference files

| File | When to read it |
|------|-----------------|
| [references/query-store.md](references/query-store.md) | Find regressions, force plans, Query Store hints, configuration |
| [references/execution-plans.md](references/execution-plans.md) | Capture & read actual plans, operators, warnings, est-vs-actual |
| [references/dmvs.md](references/dmvs.md) | Top queries, blocking, wait stats, missing/unused indexes, resource health |
| [references/indexing.md](references/indexing.md) | Clustered/covering/filtered/columnstore design + maintenance |
| [references/iqp.md](references/iqp.md) | IQP feature/compat-level matrix and how to engage/verify each |
| [references/automatic-tuning.md](references/automatic-tuning.md) | Enable/inspect auto tuning; DB vs MI differences; Azure Advisor |
| [references/antipatterns.md](references/antipatterns.md) | Non-SARGable predicates, sniffing, UDFs, conversions, RBAR, pagination |
| [references/getquestionlistv2-case-study.md](references/getquestionlistv2-case-study.md) | Real Q&A case study: dynamic proc matrix benchmarking, indexed views, row-goal hints, count rewrites, pagination, write-path safety |

## Guardrails

1. **Measure before and after** with the *same* metric; report the delta (CPU,
   logical reads, duration), not vibes.
2. **Never paste a missing-index or query hint blindly** — validate width,
   duplication, and write cost; consolidate with existing indexes.
3. **Test compatibility-level and plan changes against Query Store**; keep
   FORCE_LAST_GOOD_PLAN on as a safety net.
4. **Prefer the narrowest scope** — query/Query Store hint over database-scoped
   configuration over server-wide changes.
5. **Distinguish "slow query" from "undersized tier"** before optimizing.
6. **Know the platform split**: CREATE/DROP INDEX automatic tuning is Azure SQL
   Database only; Managed Instance gets FORCE_LAST_GOOD_PLAN.
7. **Verify current behavior** — Azure SQL evolves. Confirm version-sensitive details
   (IQP availability, compat levels, tuning options) against Microsoft Learn or the
   `microsoft-docs` MCP before asserting them.
8. **Stay in scope — do not cross engines.** This skill covers only **Azure SQL Database
   and Managed Instance**. If the question is really about another engine (PostgreSQL,
   MySQL, Oracle, SQLite), say it's outside this skill and point the user to a
   general/engine-specific SQL resource. **Do not hand over the other engine's
   procedures** — no `VACUUM`/`ANALYZE`, `pg_stat_statements`, `EXPLAIN (ANALYZE,
   BUFFERS)`, `work_mem`, autovacuum tuning, `pg_class`, MySQL `OPTIMIZE TABLE`, etc. —
   **not even "at a high level."** You may name the *equivalent Azure SQL concept* in one
   line as a bridge (e.g., "the Azure SQL analogue of `ANALYZE` is `UPDATE STATISTICS`"),
   then stop and offer Azure SQL help instead. Bridging the concept is fine; delivering
   the other engine's steps is not.
9. **Offer to measure, don't just theorize.** When tuning a specific query or proc — or
   asked a broad "why is it slow" — proactively propose running the relevant work against
   a live or non-prod database and surface the menu in *Offer to run it*: benchmarking,
   Query Store triage, index/stats audits, IQP-readiness and anti-pattern scans, and
   write-path stress validation. Ask for a connection or the actual plan *early* rather
   than waiting to be handed it.
