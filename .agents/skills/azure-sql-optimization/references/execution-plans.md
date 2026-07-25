# Execution Plans in Azure SQL

How to capture and read execution plans in Azure SQL Database and Managed Instance.
Plans are the single most important artifact for diagnosing a slow query.

## Capturing plans

### Estimated vs. actual

| Plan type | What it shows | How |
|-----------|---------------|-----|
| **Estimated** | Optimizer's plan + estimated row counts, no execution | `SET SHOWPLAN_XML ON` (then run, query is *not* executed); SSMS Ctrl+L |
| **Actual** | Plan + **actual** row counts, spills, time per operator | `SET STATISTICS XML ON`; SSMS Ctrl+M (Include Actual Execution Plan) |

Always prefer the **actual** plan for tuning — the gap between estimated and
actual rows is the primary signal of a bad plan.

```sql
-- Actual plan as XML for the next statement(s)
SET STATISTICS XML ON;
SELECT o.OrderId, o.CustomerId, o.Total
FROM dbo.Orders AS o
WHERE o.OrderDate >= '2024-01-01';
SET STATISTICS XML OFF;
```

### I/O and time, the fast first look

Run these before reaching for the graphical plan — they quantify logical reads
(the best proxy for query cost in Azure SQL) and CPU/elapsed time.

```sql
SET STATISTICS IO, TIME ON;
-- ...query...
SET STATISTICS IO, TIME OFF;
```

Read the output for: **logical reads** per table (memory/buffer pressure),
**physical reads** (cold cache), **CPU time** vs **elapsed time**
(parallelism or waits), and worktable/workfile rows (spools, spills).

### Getting plans without re-running (Query Store / cache)

In Azure SQL, **Query Store is enabled by default** and is the preferred place
to retrieve historical plans — no need for SQL Profiler/Extended Events for most
tuning. See `query-store.md`.

```sql
-- Plan from the active cache for currently/ recently running statements
SELECT qp.query_plan, st.text
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY qs.total_worker_time DESC;

-- Plan from Query Store (survives evictions, restarts, failovers)
SELECT p.plan_id, p.query_id, TRY_CAST(p.query_plan AS XML) AS query_plan
FROM sys.query_store_plan AS p
WHERE p.query_id = @query_id;
```

`SET STATISTICS PROFILE` and **Live Query Statistics** (SSMS) help on
long-running statements where you need to see row flow in real time.

## Reading the plan — what to look for

Plans read **right to left, top to bottom**. Focus on the fattest arrows
(most rows) and the operators consuming the most "cost %".

### Data access operators

| Operator | Meaning | Action |
|----------|---------|--------|
| **Clustered/Index Seek** | Targeted B-tree navigation | Usually good |
| **Index Scan** | Reads the whole index | Fine for small tables / large result sets; bad when you expected a seek |
| **Table Scan** | Heap, full read | Add a clustered index or supporting nonclustered index |
| **Key Lookup / RID Lookup** | Fetches columns not in the nonclustered index, once per row | Make the index **covering** (add `INCLUDE` columns) — see `indexing.md` |

A **Seek** that still reads many rows is not automatically good — check the
predicate is a true *seek predicate*, not a residual `Predicate`.

### Join operators

| Operator | Best for | Red flag |
|----------|----------|----------|
| **Nested Loops** | Small outer input + indexed inner | Huge outer row count = O(n) lookups |
| **Hash Match** | Large, unsorted inputs | Hash spill warning; appears where a seek+loop was expected |
| **Merge** | Two large, pre-sorted inputs | Forced sort feeding the merge |

### Common warnings (triangle on the operator)

- **Implicit conversion** (`CONVERT_IMPLICIT`) in a predicate — usually a data
  type mismatch that defeats an index seek. Fix the type, not the query plan.
- **Spill to tempdb** (Sort/Hash) — underestimated memory grant; often fixed by
  better stats, batch mode, or memory grant feedback (IQP).
- **No Join Predicate** — accidental cross join.
- **Excessive Grant** — large `MemoryGrantInfo` vs. rows used; watch for
  `RESOURCE_SEMAPHORE` waits on busy databases.
- **Missing Index** green hint — a *suggestion*, not an order. Validate before
  applying; see `indexing.md` and `dmvs.md`.

### Estimated vs. actual row skew

The biggest lever. If `Estimated Number of Rows` is wildly different from
`Actual Number of Rows`:

1. Update statistics (`UPDATE STATISTICS dbo.Orders WITH FULLSCAN;`).
2. Look for non-SARGable predicates or local variables hiding values from the
   optimizer (see `antipatterns.md`).
3. Consider IQP features (CE feedback, table variable deferred compilation,
   interleaved execution) — see `iqp.md`.

## Plan-affecting settings to verify

- **Database compatibility level** (`SELECT compatibility_level FROM sys.databases`)
  gates the cardinality estimator and most IQP features.
- `LEGACY_CARDINALITY_ESTIMATION`, `PARAMETER_SNIFFING`, `MAXDOP` via
  `ALTER DATABASE SCOPED CONFIGURATION` — these silently change every plan.

## Anti-patterns

- ❌ Tuning from the **estimated** plan alone when the problem is bad estimates.
- ❌ Chasing the highest "cost %" operator — costs are *estimates*; verify with
  actual rows and `STATISTICS IO`.
- ❌ Adding the green missing-index hint verbatim without checking width,
  duplication, and write overhead.
