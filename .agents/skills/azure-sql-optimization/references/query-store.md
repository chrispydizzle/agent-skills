# Query Store for Azure SQL

Query Store is the flight recorder for your database: it captures queries, their
**execution plans**, **runtime stats**, and **waits** over time. In Azure SQL
Database and Managed Instance it is **enabled by default**. It is the preferred
source for historical tuning because, unlike DMV counters, it survives restarts,
failovers, and scaling.

## Why it matters for tuning

1. Find the heaviest queries and **plan regressions** (a query that got slower
   because its plan changed).
2. **Compare plans** for the same query side by side.
3. **Force** a known-good plan, or apply a **Query Store hint** — both *without
   changing application code*.

## Configuration

```sql
-- Inspect current settings
SELECT actual_state_desc, query_capture_mode_desc, wait_stats_capture_mode_desc,
       max_storage_size_mb, current_storage_size_mb, stale_query_threshold_days,
       interval_length_minutes
FROM sys.database_query_store_options;

-- Recommended baseline (already on by default in Azure SQL; tune as needed)
ALTER DATABASE CURRENT SET QUERY_STORE = ON
( OPERATION_MODE = READ_WRITE,
  QUERY_CAPTURE_MODE = AUTO,            -- skips trivial/infrequent queries
  WAIT_STATS_CAPTURE_MODE = ON,
  MAX_STORAGE_SIZE_MB = 1000,
  CLEANUP_POLICY = ( STALE_QUERY_THRESHOLD_DAYS = 30 ) );
```

If Query Store flips to `READ_ONLY` (storage full), increase `MAX_STORAGE_SIZE_MB`
or clear it (`ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;`).

## Catalog views

| View | Contains |
|------|----------|
| `sys.query_store_query` / `sys.query_store_query_text` | Query identity + SQL text |
| `sys.query_store_plan` | Captured plans; `is_forced_plan` flag |
| `sys.query_store_runtime_stats` | Duration, CPU, reads, executions per interval |
| `sys.query_store_runtime_stats_interval` | Time buckets |
| `sys.query_store_wait_stats` | Per-query wait categories |
| `sys.query_store_query_hints` | Applied Query Store hints + failures |

## Find the worst queries (last 24h)

```sql
SELECT TOP (20)
    q.query_id, qt.query_sql_text,
    SUM(rs.count_executions)                          AS executions,
    SUM(rs.avg_cpu_time   * rs.count_executions)/1000 AS total_cpu_ms,
    SUM(rs.avg_duration   * rs.count_executions)/1000 AS total_duration_ms,
    COUNT(DISTINCT p.plan_id)                         AS plan_count
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p        ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS rsi
     ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(hour, -24, SYSUTCDATETIME())
GROUP BY q.query_id, qt.query_sql_text
ORDER BY total_cpu_ms DESC;
```

`plan_count > 1` is your regression shortlist — the same query is running under
multiple plans.

## Force / unforce a plan

After identifying the good `plan_id` for a `query_id` (SSMS "Regressed Queries"
report or the query above):

```sql
EXEC sys.sp_query_store_force_plan   @query_id = 42, @plan_id = 17;
-- later, to release it:
EXEC sys.sp_query_store_unforce_plan @query_id = 42, @plan_id = 17;
```

Or let Azure do it automatically: the **FORCE_LAST_GOOD_PLAN** automatic-tuning
option (availability and default state depend on service/tier and server settings;
often enabled by default for *new Azure SQL Database logical servers*). It forces
the last good plan on detected regressions and self-reverts if it doesn't help —
see `automatic-tuning.md`.

## Query Store hints (shape a plan without code changes)

**Applies to:** SQL Server 2022+, Azure SQL Database, Azure SQL Managed Instance.
Inject a query hint by `query_id` instead of editing T-SQL or using plan guides.
Hints persist across restarts/failovers and override statement-level hints and plan
guides.

```sql
-- Force a recompile (e.g., to defeat a bad sniffed plan) without touching code
EXEC sys.sp_query_store_set_hints @query_id = 42, @query_hints = N'OPTION(RECOMPILE)';

-- Cap parallelism for one query
EXEC sys.sp_query_store_set_hints @query_id = 42, @query_hints = N'OPTION(MAXDOP 1)';

-- Pin an older CE / compat for just this query
EXEC sys.sp_query_store_set_hints @query_id = 42,
     @query_hints = N'OPTION(USE HINT(''QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_110''))';

-- Remove hints
EXEC sys.sp_query_store_clear_hints @query_id = 42;
```

Notes: not supported for statements eligible for simple parameterization; `RECOMPILE`
is ignored under database-level forced parameterization (warning 12461); contradictory
hints are ignored rather than failing the query. Check applied hints / failures in
`sys.query_store_query_hints`.

## Portal & SSMS

- **SSMS**: Database → Query Store → *Regressed Queries*, *Top Resource Consuming
  Queries*, *Queries With Forced Plans*. Force/compare plans from the UI.
- **Azure portal (Azure SQL Database)**: *Query Performance Insight* surfaces the
  same data and the top CPU/DTU queries.

## Typical workflow

1. Open *Top Resource Consuming* / *Regressed Queries*.
2. Compare the regressed plan vs. the prior fast plan.
3. **Force** the good plan (quick mitigation) **or** add a **Query Store hint**.
4. Address root cause (index, stats, query rewrite, compat level) and then unforce.
