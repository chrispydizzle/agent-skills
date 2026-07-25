# Diagnostic DMVs & Catalog Views for Azure SQL

Dynamic management views (DMVs) are the command-line way to find what's slow.
In Azure SQL, **Query Store** (see `query-store.md`) is often the better source for
*historical* analysis because DMV counters reset on restart/failover/scale, but
DMVs are essential for **live** state and instance health.

> Permissions: most require `VIEW DATABASE STATE` (Azure SQL Database) or
> `VIEW SERVER STATE` (Managed Instance).

## Top resource-consuming queries (from cache)

```sql
SELECT TOP (20)
    qs.execution_count,
    qs.total_worker_time   / 1000 AS total_cpu_ms,
    qs.total_elapsed_time  / 1000 AS total_elapsed_ms,
    qs.total_logical_reads,
    (qs.total_worker_time / qs.execution_count) / 1000 AS avg_cpu_ms,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
          ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS stmt,
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
ORDER BY qs.total_worker_time DESC;   -- swap to total_logical_reads for I/O hogs
```

## Live requests & blocking

```sql
-- What's running right now and what's blocking it
SELECT r.session_id, r.status, r.wait_type, r.wait_time, r.blocking_session_id,
       r.cpu_time, r.logical_reads, r.command,
       SUBSTRING(t.text, (r.statement_start_offset/2)+1, 200) AS stmt
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE r.session_id <> @@SPID
ORDER BY r.cpu_time DESC;

-- The blocking chain
SELECT wt.blocking_session_id, wt.session_id AS blocked_session_id,
       wt.wait_duration_ms, wt.wait_type, wt.resource_description
FROM sys.dm_os_waiting_tasks AS wt
WHERE wt.blocking_session_id IS NOT NULL;
```

## Wait statistics — where time goes

In **Azure SQL Database**, use the database-scoped `sys.dm_db_wait_stats`.
In **Managed Instance / SQL Server**, use `sys.dm_os_wait_stats`.
Query Store also exposes per-query waits via `sys.query_store_wait_stats`.

```sql
SELECT TOP (15) wait_type, waiting_tasks_count,
       wait_time_ms, wait_time_ms - signal_wait_time_ms AS resource_wait_ms
FROM sys.dm_db_wait_stats           -- sys.dm_os_wait_stats on MI
WHERE wait_type NOT IN ('CLR_SEMAPHORE','SLEEP_TASK','BROKER_TASK_STOP',
       'XE_TIMER_EVENT','XE_DISPATCHER_WAIT','LAZYWRITER_SLEEP','SQLTRACE_INCREMENTAL_FLUSH_SLEEP')
ORDER BY wait_time_ms DESC;
```

| Wait | Usual meaning | Direction |
|------|---------------|-----------|
| `PAGEIOLATCH_*` | Reading data pages from storage | Add indexes / reduce reads / more memory tier |
| `RESOURCE_SEMAPHORE` | Queries waiting for memory grants | Fix over-estimated grants, spills (see IQP) |
| `CXPACKET` / `CXCONSUMER` | Parallelism | Tune `MAXDOP` / `COST THRESHOLD`; fix big scans |
| `LCK_M_*` | Blocking / lock contention | Shorten transactions, fix indexes, use RCSI |
| `SOS_SCHEDULER_YIELD` | CPU pressure | Reduce CPU per query / scale up |
| `WRITELOG` | Transaction log flush | Batch writes, check log throughput limits |
| `PAGELATCH_*` (tempdb) | tempdb allocation contention | Reduce tempdb spills, fewer temp objects |

## Missing index suggestions

The optimizer records indexes it *wished* existed. Treat as hints, not orders.

```sql
SELECT TOP (20)
    ROUND(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans), 0) AS score,
    s.user_seeks, s.user_scans, s.last_user_seek,
    d.statement AS [table],
    d.equality_columns, d.inequality_columns, d.included_columns
FROM sys.dm_db_missing_index_group_stats AS s
JOIN sys.dm_db_missing_index_groups AS g  ON s.group_handle = g.index_group_handle
JOIN sys.dm_db_missing_index_details AS d ON g.index_handle  = d.index_handle
ORDER BY score DESC;
```

Caveats: capped at 500 suggestions, reset on restart/failover, never consolidated,
ignore key **column order**, and over-suggest wide `INCLUDE` lists. Validate before
creating — and on Azure SQL **Database**, prefer the automatic-tuning **CREATE INDEX**
recommendation, which also validates and auto-reverts (see `automatic-tuning.md`).

## Index usage — find unused / write-heavy indexes

```sql
SELECT OBJECT_NAME(i.object_id) AS [table], i.name AS [index],
       us.user_seeks, us.user_scans, us.user_lookups, us.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
       ON us.object_id = i.object_id AND us.index_id = i.index_id
      AND us.database_id = DB_ID()
WHERE i.index_id > 0 AND OBJECTPROPERTY(i.object_id,'IsUserTable') = 1
ORDER BY us.user_updates DESC;       -- high updates + ~0 reads = drop candidate
```

Counters reset on restart/failover/scale — only interpret over a known uptime
window (`sys.dm_os_sys_info.sqlserver_start_time`).

## Fragmentation & statistics

```sql
-- Fragmentation (LIMITED is cheap)
SELECT OBJECT_NAME(ps.object_id) AS [table], i.name,
       ps.avg_fragmentation_in_percent, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.page_count > 1000 AND ps.avg_fragmentation_in_percent > 10
ORDER BY ps.avg_fragmentation_in_percent DESC;

-- Stale statistics
SELECT OBJECT_NAME(s.object_id) AS [table], s.name AS stats_name,
       sp.last_updated, sp.rows, sp.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE sp.modification_counter > 0
ORDER BY sp.modification_counter DESC;
```

## Azure SQL resource health (are you hitting tier limits?)

```sql
-- Azure SQL Database: last hour, ~15-second samples, as % of tier limit
SELECT end_time, avg_cpu_percent, avg_data_io_percent, avg_log_write_percent,
       avg_memory_usage_percent
FROM sys.dm_db_resource_stats
ORDER BY end_time DESC;
```

- **Azure SQL Database**: `sys.dm_db_resource_stats` (current DB, last hour) and
  `sys.resource_stats` (in `master`, longer history); `sys.dm_user_db_resource_governance`
  for effective limits.
- **Managed Instance**: use `sys.server_resource_stats` for instance CPU/IO/memory
  history and `sys.dm_instance_resource_governance` for limits.

Confirm whether the bottleneck is the query or the **service tier** before
optimizing further.
