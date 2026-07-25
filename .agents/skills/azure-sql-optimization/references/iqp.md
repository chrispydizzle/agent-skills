# Intelligent Query Processing (IQP) in Azure SQL

IQP is a family of optimizer/runtime features that improve existing workloads
**with little or no code change**. Most are **gated by the database compatibility
level**, so the single highest-leverage IQP action is often:

```sql
SELECT name, compatibility_level FROM sys.databases;   -- current level

-- Test first, then raise (160 = SQL Server 2022 / current Azure SQL)
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;
```

> Raising compat level changes plans. **Use Query Store** (enabled by default) to
> catch regressions and force the last good plan — see `query-store.md`. A safe
> pattern: bump compat level while keeping the older CE via
> `ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;`
> then re-test removing it.

## Feature / compatibility-level matrix

Available in **Azure SQL Database and Managed Instance** (both run the evergreen
engine; exact per-feature availability is governed by compatibility level). See the
authoritative matrix: *Intelligent query processing in SQL databases* on Microsoft
Learn.

| Feature | Min compat | What it fixes |
|---------|:---------:|---------------|
| Batch mode Adaptive Joins | 140 | Defers Hash vs. Nested Loops choice until first input is scanned |
| Interleaved execution (MSTVFs) | 140 | Replaces the fixed 100-row guess for multi-statement TVFs |
| Batch mode memory grant feedback | 140 | Corrects over/under-sized memory grants (spills, `RESOURCE_SEMAPHORE`) |
| Scalar UDF inlining | 150 | Turns per-row scalar UDFs into set-based expressions |
| Table variable deferred compilation | 150 | Uses real table-variable row counts instead of the 1-row guess |
| Batch mode on rowstore | 150 | Batch-mode CPU efficiency for analytics **without** a columnstore index |
| Row mode memory grant feedback | 150 | Memory grant correction for rowstore plans |
| Approximate count distinct (`APPROX_COUNT_DISTINCT`) | any | Fast approximate distinct counts (SQL 2019+) |
| Approximate percentile (`APPROX_PERCENTILE_*`) | any | Fast approximate percentiles (SQL 2022+) |
| Parameter Sensitive Plan (PSP) optimization | 160 | Multiple cached plans for one parameterized query (skewed data) |
| Cardinality estimation (CE) feedback | 160 | Learns and adjusts bad CE assumptions over time (uses Query Store) |
| Degree of parallelism (DOP) feedback | 160 | Lowers DOP for queries that don't benefit from parallelism (uses Query Store) |
| Percentile / persistence memory grant feedback | 160 | Stabilizes grants across varying inputs; persists via Query Store |
| Optimized plan forcing | (Query Store) | Reduces recompile cost for forced plans |

## Highest-impact features, in practice

- **PSP optimization (160)** — the modern answer to *parameter sniffing* on skewed
  data. Often removes the need for `OPTION(RECOMPILE)` workarounds. See
  `antipatterns.md` §4.
- **Memory grant feedback** — directly attacks **tempdb spills** and
  `RESOURCE_SEMAPHORE` waits surfaced in `dmvs.md`.
- **Scalar UDF inlining (150)** — frequently a 5–50× win on UDF-heavy reporting
  queries. Confirm a UDF qualifies:
  ```sql
  SELECT name, is_inlineable FROM sys.sql_modules m
  JOIN sys.objects o ON o.object_id = m.object_id WHERE o.type = 'FN';
  ```
- **Batch mode on rowstore (150)** — CPU relief for scan/aggregate-heavy queries on
  OLTP schemas that can't take a columnstore index.

## Verifying a feature engaged

- **Execution plan attributes**: e.g., `ContainsInterleavedExecutionCandidates`,
  actual *batch mode* on scan operators, Adaptive Join operator, `MemoryGrantInfo`
  with feedback adjustments. (See `execution-plans.md`.)
- **Query Store**: feedback features (CE/DOP/memory grant) record their adjustments
  and persist them; review plan variability there.

## Turning a feature off (without lowering compat level)

Each feature has a targeted `ALTER DATABASE SCOPED CONFIGURATION` switch and/or a
statement-level `USE HINT`, so you can keep the modern compat level and disable just
the one feature that regressed. Examples:

```sql
ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = OFF;
-- per query:
... OPTION (USE HINT('DISALLOW_BATCH_MODE'));
... OPTION (USE HINT('DISABLE_INTERLEAVED_EXECUTION_TVF'));
... OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));
```

Prefer the **narrowest** scope (query hint or Query Store hint) over database-wide
switches.
