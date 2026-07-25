# Automatic Tuning & Performance Recommendations

Azure SQL can tune itself: it continuously monitors workloads, applies changes
during low-utilization windows, **validates** that they help, and **auto-reverts**
if they don't. Built on the same engine as SQL Server automatic tuning and on Query
Store.

## The three options

| Option | Does | Azure SQL Database | Azure SQL Managed Instance |
|--------|------|:------------------:|:--------------------------:|
| **FORCE_LAST_GOOD_PLAN** (automatic plan correction) | Detects a query whose new plan is slower than its previous good plan and forces the last good plan; reverts if no gain | ✅ | ✅ (only this one) |
| **CREATE_INDEX** | Finds and creates beneficial indexes, then verifies improvement | ✅ | ❌ |
| **DROP_INDEX** | Drops duplicate and long-unused (90-day) indexes | ✅ | ❌ |

**Azure defaults** (new logical servers): `FORCE_LAST_GOOD_PLAN` = **ON**,
`CREATE_INDEX` = OFF, `DROP_INDEX` = OFF.

> Managed Instance supports **only** FORCE_LAST_GOOD_PLAN. CREATE/DROP INDEX are
> Azure SQL Database (single + pooled) only.

## Enable / inspect (T-SQL)

```sql
-- Inherit the logical-server configuration (recommended for many DBs)
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING = INHERIT;

-- Or set explicitly on this database
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING
    (FORCE_LAST_GOOD_PLAN = ON, CREATE_INDEX = ON, DROP_INDEX = ON);

-- See effective state (incl. "Disabled by the system" when Azure pauses tuning)
SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;
```

Configuring at the **server level** and inheriting per database is the recommended
approach for managing many databases. In the Azure portal this is the
*Automatic tuning* blade (server and database scope).

## Important behaviors & caveats

- **Validation & auto-revert** happen only when Azure applies the recommendation for
  you. Depending on query frequency, validation takes ~30 min to 72 hours; a
  detected regression is reverted immediately.
- If you apply a recommendation **manually via T-SQL**, that automatic validation
  and reversal **do not** apply; the recommendation stays listed ~24–48 h.
- **CREATE_INDEX**: won't generate a recommendation if it would push storage over
  ~90% of max size, and skips tables whose clustered index/heap is larger than
  10 GB. Index creation runs during low utilization and isn't cancelled mid-flight.
- **DROP_INDEX**: never drops unique indexes (including PK/unique-constraint
  indexes); can disable itself when the workload uses index hints or partition
  switching. On **Premium / Business Critical**, it drops duplicate indexes but
  never unused ones.
- Tuning history is retained **21 days** for Azure SQL Database (portal or
  `Get-AzSqlDatabaseRecommendedAction`); stream longer history via the
  **AutomaticTuning** diagnostic setting.

## Manual performance recommendations (Azure Advisor)

Even with automatic application off, Azure surfaces the same recommendations to
review and apply on demand:

- **Azure portal** → SQL database → *Performance recommendations* (and **Azure
  Advisor** → Performance).
- **PowerShell**: `Get-AzSqlDatabaseRecommendedAction`.
- **REST API**: Server Automatic Tuning / recommended actions.

## How it fits the tuning loop

1. Keep **FORCE_LAST_GOOD_PLAN ON** as a safety net against plan regressions
   (complements Query Store plan forcing — see `query-store.md`).
2. On Azure SQL **Database**, consider enabling **CREATE_INDEX** / **DROP_INDEX** to
   let the platform maintain indexes — but still review recommendations, since the
   missing-index engine can suggest wide or near-duplicate indexes (see
   `indexing.md`, `dmvs.md`).
3. On **Managed Instance**, automate indexing yourself (validated against Query
   Store) since only plan correction is available.
