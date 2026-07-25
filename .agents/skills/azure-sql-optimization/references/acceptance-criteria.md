# Acceptance Criteria: azure-sql-optimization

**Skill**: `azure-sql-optimization`
**Scope**: Azure SQL Database + Azure SQL Managed Instance query optimization
**Purpose**: Skill testing acceptance criteria — correct vs. incorrect guidance the
skill should produce.

---

## 1. Methodology

### 1.1 ✅ CORRECT: Measure first, tune from the actual plan

- Confirms whether the bottleneck is the query or the **service tier**
  (`sys.dm_db_resource_stats`) before optimizing.
- Ranks queries by total CPU / logical reads / duration via **Query Store** or DMVs.
- Uses the **actual** execution plan (`SET STATISTICS XML ON`), not estimated alone.

### 1.2 ❌ INCORRECT: Optimizing by guesswork

- Adds indexes or rewrites without identifying the top consumer.
- Concludes from the **estimated** plan when the issue is bad cardinality estimates.

---

## 2. SARGable predicates

### 2.1 ✅ CORRECT: Bare column, range rewrite

```sql
WHERE o.OrderDate >= '2024-01-01' AND o.OrderDate < '2025-01-01'
```

### 2.2 ❌ INCORRECT: Function on the column (non-SARGable)

```sql
WHERE YEAR(o.OrderDate) = 2024          -- forces a scan
WHERE UPPER(c.Email) = 'A@B.COM'        -- forces a scan; collation is already CI
```

---

## 3. Data-type matching (implicit conversion)

### 3.1 ✅ CORRECT: Match parameter type to column type

- Sends `VARCHAR`/`DbType.AnsiString` for a `VARCHAR` column; flags
  `CONVERT_IMPLICIT` warnings in the plan as the root cause.

### 3.2 ❌ INCORRECT: Ignoring NVARCHAR-vs-VARCHAR conversion

- Recommends an index without noticing an `NVARCHAR` parameter scans a `VARCHAR`
  column.

---

## 4. Indexing

### 4.1 ✅ CORRECT: Covering index to remove key lookups

```sql
CREATE INDEX IX_Orders_Customer_Status ON dbo.Orders (CustomerId, Status)
    INCLUDE (OrderDate, Total);
```

- Orders composite keys: equality columns first, then range, then sort.
- Treats missing-index DMV/plan suggestions as **candidates** to validate and
  consolidate.

### 4.2 ❌ INCORRECT: Blindly applying suggestions / over-indexing

```sql
-- Creating the green missing-index hint verbatim, plus one single-column index
-- per column, with no consolidation or write-cost check.
```

---

## 5. Query Store (correct object names)

### 5.1 ✅ CORRECT: Force a plan / apply a hint by query_id

```sql
EXEC sys.sp_query_store_force_plan @query_id = 42, @plan_id = 17;
EXEC sys.sp_query_store_set_hints  @query_id = 42, @query_hints = N'OPTION(RECOMPILE)';
EXEC sys.sp_query_store_clear_hints @query_id = 42;
```

- Notes Query Store is **enabled by default** in Azure SQL.
- Uses catalog views `sys.query_store_query`, `sys.query_store_plan`,
  `sys.query_store_runtime_stats`.

### 5.2 ❌ INCORRECT: Wrong/legacy mechanisms

```sql
-- Inventing procs or using SQL Server box-only paths as the first resort:
EXEC sp_force_plan ...                 -- not a real proc
-- Reaching for plan guides before Query Store hints.
```

---

## 6. Automatic tuning (platform split)

### 6.1 ✅ CORRECT: Right options per platform

```sql
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING
    (FORCE_LAST_GOOD_PLAN = ON, CREATE_INDEX = ON, DROP_INDEX = ON);   -- Azure SQL Database
SELECT name, actual_state_desc FROM sys.database_automatic_tuning_options;
```

- States **Managed Instance supports only FORCE_LAST_GOOD_PLAN**.
- Notes Azure default: FORCE_LAST_GOOD_PLAN ON, CREATE/DROP INDEX OFF.

### 6.2 ❌ INCORRECT: Claiming CREATE/DROP INDEX on Managed Instance

- Recommends enabling `CREATE_INDEX`/`DROP_INDEX` automatic tuning on MI.
- Asserts manual T-SQL-applied recommendations get auto-validation/rollback (they
  don't).

---

## 7. Intelligent Query Processing / compatibility level

### 7.1 ✅ CORRECT: Raise compat level, gated and tested

```sql
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;   -- unlocks PSP, CE/DOP feedback...
```

- Recommends validating with Query Store and keeping FORCE_LAST_GOOD_PLAN on.
- Maps features to **minimum compat level** (e.g., PSP/CE/DOP feedback = 160; UDF
  inlining / batch-mode-on-rowstore = 150; adaptive joins / interleaved = 140).

### 7.2 ❌ INCORRECT: Wrong gating

- Claims PSP optimization works at compat 150, or that IQP needs a SQL VM.

---

## 8. Parameter sniffing mitigations (least-invasive first)

### 8.1 ✅ CORRECT: Prefer PSP / Query Store hint before code/DB-wide changes

- Order: compat 160 (PSP) → Query Store hint (`RECOMPILE`/`OPTIMIZE FOR`) →
  in-code `OPTION(...)` → (last) `PARAMETER_SNIFFING = OFF` database scope.

### 8.2 ❌ INCORRECT: Reaching for the blunt instrument first

```sql
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF;  -- whole DB, last resort
```

---

## 9. Concurrency

### 9.1 ✅ CORRECT: Don't use NOLOCK as a tuning tool

- Notes `READ_COMMITTED_SNAPSHOT` is **ON by default** in Azure SQL Database;
  readers don't block writers — fix the index/query.

### 9.2 ❌ INCORRECT: Sprinkling NOLOCK

```sql
SELECT ... FROM dbo.Orders WITH (NOLOCK);   -- dirty reads, not a fix
```

---

## 10. Tooling correctness

### 10.1 ✅ CORRECT: Azure SQL-appropriate DMVs

- `sys.dm_db_resource_stats` / `sys.resource_stats` for tier health.
- `sys.dm_db_wait_stats` (Azure SQL Database) vs `sys.dm_os_wait_stats` (MI).
- `sys.dm_db_missing_index_*`, `sys.dm_db_index_usage_stats`.

### 10.2 ❌ INCORRECT: Box-SQL-only assumptions

- Relying on `sys.dm_os_wait_stats` as database-scoped in Azure SQL Database, or
  recommending SQL Server Agent / Profiler-first workflows.

---

## 11. Scope discipline

### 11.1 ✅ CORRECT: Azure SQL focus

- Stays on Azure SQL Database / Managed Instance tooling and behavior.

### 11.2 ❌ INCORRECT: Generic cross-engine advice

- Gives MySQL/PostgreSQL `EXPLAIN ANALYZE`, `VACUUM`, `pg_stat_statements`, or
  `pg_class` guidance — that belongs to a general SQL skill, not this one.

---

## 12. Hot dynamic stored procedures

### 12.1 ✅ CORRECT: Matrix benchmark and isolate each branch

- Traces wrapper-to-builder parameter semantics before tuning, especially
  `@Page`, `@PageSize`, `@Offset`, and `@Rows`.
- Benchmarks each meaningful sort/filter/page-depth branch with actual plans,
  logical reads, CPU/duration, and sort/spill presence.
- Keeps a no-regression control for dominant paths expected not to change.
- Verifies rewritten count/filter branches return byte-identical results.

### 12.2 ✅ CORRECT: Indexed views with write-path discipline

- Uses indexed views only when the view grain and indexed key match the hot query
  shape.
- Checks actual plan object references because Azure SQL may auto-match indexed
  views the SQL text does not name.
- Separates build-time concerns (`ONLINE = ON`) from steady-state indexed-view
  maintenance and validates concurrency/write-path tests.

### 12.3 ✅ CORRECT: Hints and pagination are verified, not assumed

- Keeps `RECOMPILE` when the optimal dynamic-SQL plan depends on offset/filter
  selectivity.
- Tests `DISABLE_OPTIMIZER_ROWGOAL` with `RECOMPILE` still present and across
  shallow and deep pages before keeping or removing it.
- Uses `TOP (@Offset + @Rows)` when `@Offset` is already a row offset, not
  `TOP ((@Offset + 1) * @Rows)`.

### 12.4 ❌ INCORRECT: Single-path or cache-contaminated conclusions

- Declares success from page 1 only, without mid/deep-page coverage.
- Compares estimated plans or cached-plan artifacts instead of actual plans with
  controlled recompilation.
- Adds an indexed view for read speed without checking write-path deadlocks or
  SQL project/deployment wiring.

---

## 13. Proactive benchmarking & featureset

### 13.1 ✅ CORRECT: Offer to measure against a live/non-prod database

- When tuning a specific query or proc, **proactively offers to benchmark** the change
  against a live (or non-production) database instead of waiting for the user to supply
  access.
- Surfaces concrete capabilities: capturing the **actual** plan, `SET STATISTICS IO, TIME`,
  Query Store top-consumer/regression pulls, the before/after matrix, and reporting deltas
  (CPU, logical reads, duration, spills).
- Asks for a connection or the actual plan **early**, and uses a SQL connection / MCP tool
  to measure when one is available.

### 13.2 ❌ INCORRECT: Theory-only, waits to be handed access

- Gives only theoretical tweaks and never offers to benchmark or measure empirically.
- Waits for the user to volunteer live-server access before even suggesting that measuring
  against the live database is possible.

---

## 14. Proactive diagnostics & audit offers

For each, ✅ = proactively offers to *run it against the user's DB* (and asks for a
connection / the actual plan), naming the concrete DMV/Query Store object; ❌ = only
theorizes or waits to be handed access/results.

### 14.1 Query Store triage

- ✅ Offers to rank the worst CPU/IO/duration queries from Query Store and surface the
  regression shortlist (`plan_count > 1`), instead of asking the user to name the query.
- ❌ Gives generic "look at the slow query" advice with no offer to pull/rank them.

### 14.2 Index audit

- ✅ Offers to harvest missing-index *and* unused/write-heavy indexes
  (`sys.dm_db_missing_index_*`, `sys.dm_db_index_usage_stats`) and return a consolidated,
  validated change-set.
- ❌ Points at the missing-index DMV and suggests creating rows verbatim, no consolidation.

### 14.3 IQP / compat-level readiness

- ✅ Offers to check the current compat level and enumerate unused IQP features, with a
  gated, Query-Store-validated upgrade plan.
- ❌ Says "raise compat level" with no readiness assessment, or only describes IQP abstractly.

### 14.4 Statistics freshness audit

- ✅ After a large data change, offers to find stale stats (high `modification_counter`)
  and refresh the ones that matter; links stale stats to bad estimates.
- ❌ Ignores statistics freshness / doesn't offer to audit-refresh after a bulk change.

### 14.5 Anti-pattern scan

- ✅ Offers to scan a supplied proc or actual plan for the concrete anti-pattern list and
  asks for the proc/plan.
- ❌ Gives only vague advice without offering to scan the actual proc/plan.

### 14.6 Write-path / deadlock stress validation

- ✅ Before shipping an indexed view / hot-path index, offers a write-path / deadlock
  stress test and separates read-speedup from write-path safety.
- ❌ Treats an indexed view as read-only-safe; skips write-path validation.
