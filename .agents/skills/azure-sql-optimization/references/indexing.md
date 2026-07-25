# Indexing for Azure SQL

Indexing is the highest-leverage tuning tool. The goal: let the optimizer **seek**
the rows it needs and **cover** the columns it returns, without over-indexing writes.

## Clustered index (the table's physical order)

Every OLTP table should have a clustered index. Good clustering key = **narrow,
unique, static, ever-increasing** (e.g., an `IDENTITY`/`BIGINT` surrogate or
sequential key). A wide or random clustering key (e.g., random `GUID`) bloats every
nonclustered index (they carry the clustering key) and causes page splits.

```sql
-- Sequential surrogate key is a good default clustering key
CREATE TABLE dbo.Orders (
    OrderId   BIGINT IDENTITY CONSTRAINT PK_Orders PRIMARY KEY,  -- clustered
    CustomerId INT NOT NULL,
    OrderDate  DATETIME2(0) NOT NULL,
    Status     TINYINT NOT NULL,
    Total      DECIMAL(12,2) NOT NULL
);
```

If you must cluster on a random GUID, use `NEWSEQUENTIALID()` or a sequential
surrogate instead, and consider a higher fill factor.

## Nonclustered + covering indexes (kill key lookups)

A **Key Lookup** in the plan means the nonclustered index found the row but had to
jump to the clustered index for extra columns. Make the index **covering** with
`INCLUDE` so the query is satisfied from the index alone.

```sql
-- Query: SELECT OrderId, OrderDate, Total FROM Orders WHERE CustomerId=@id AND Status=1
-- ✅ Key columns for the WHERE, INCLUDE the projected columns
CREATE INDEX IX_Orders_Customer_Status
    ON dbo.Orders (CustomerId, Status)
    INCLUDE (OrderDate, Total);
```

### Composite key column order

Order key columns by how they're used: **equality predicates first**, then the
**range/inequality** column, then `ORDER BY` columns. Most-selective-first only
matters after the equality columns are placed. A single composite index usually
beats several single-column indexes the optimizer must combine.

```sql
-- WHERE CustomerId = @c AND OrderDate >= @from ORDER BY OrderDate
CREATE INDEX IX_Orders_Customer_Date ON dbo.Orders (CustomerId, OrderDate)
    INCLUDE (Total);
```

## Filtered indexes (skewed columns, soft deletes, statuses)

Smaller, cheaper indexes for a hot subset of rows.

```sql
-- Only index the small set of open orders
CREATE INDEX IX_Orders_Open ON dbo.Orders (CustomerId, OrderDate)
    WHERE Status IN (0, 1);

-- Index only non-deleted rows
CREATE INDEX IX_Customers_Active ON dbo.Customers (Email)
    WHERE IsDeleted = 0;
```

Note: a query must use a literal/compatible predicate matching the filter to use a
filtered index, and parameterized queries may need `OPTION (RECOMPILE)`.

## Columnstore indexes (analytics / large scans)

For aggregation/scan-heavy ("OLAP") tables, columnstore gives order-of-magnitude
gains via compression + batch mode.

```sql
-- Data-warehouse fact table: clustered columnstore
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales ON dbo.FactSales;

-- HTAP: nonclustered columnstore over an OLTP rowstore table
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Orders ON dbo.Orders (OrderDate, Status, Total);
```

Availability depends on service tier (vCore tiers and DTU Premium / Standard S3+;
**not** Basic/S0–S2 — verify for your tier). For rowstore tables that are CPU-bound
on analytics but can't take a columnstore index, **batch mode on rowstore**
(compat 150) helps automatically — see `iqp.md`.

## Validate, consolidate, and don't over-index

- Each nonclustered index adds cost to every `INSERT`/`UPDATE`/`DELETE` and uses
  storage. Audit usage with `sys.dm_db_index_usage_stats` (see `dmvs.md`).
- **Consolidate** overlapping indexes: an index on `(A)` is redundant if
  `(A, B)` exists. Merge missing-index suggestions into existing indexes rather
  than creating near-duplicates.
- Treat missing-index DMV/plan hints as **candidates** — check width, duplication,
  and write impact first.
- On Azure SQL **Database**, let automatic tuning **CREATE INDEX / DROP INDEX**
  propose and validate changes (see `automatic-tuning.md`).

## Maintenance: rebuild, reorganize, statistics

```sql
-- Online + resumable rebuild avoids long blocking (tier-dependent)
ALTER INDEX IX_Orders_Customer_Status ON dbo.Orders
    REBUILD WITH (ONLINE = ON, RESUMABLE = ON);

-- Reorganize for light fragmentation
ALTER INDEX IX_Orders_Customer_Status ON dbo.Orders REORGANIZE;
```

Rules of thumb (use the fragmentation query in `dmvs.md`, ignore tables < ~1000
pages): **reorganize** ~5–30%, **rebuild** > 30%. Fragmentation matters far less for
seek-heavy SSD workloads than for scans.

**Statistics drive estimates** more than fragmentation drives speed. Azure SQL
keeps `AUTO_CREATE_STATISTICS` / `AUTO_UPDATE_STATISTICS` on by default; for volatile
big tables, add targeted updates:

```sql
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;          -- after large data change
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS_ASYNC ON;  -- avoid compile stalls
```

## Anti-patterns

- ❌ One single-column index per column "just in case" — write amplification.
- ❌ Indexing a very low-selectivity column alone (e.g., a 2-value flag) — use a
  **filtered** index instead.
- ❌ Wide clustering keys / random GUID clusters — bloats all nonclustered indexes.
- ❌ Creating every missing-index suggestion verbatim — consolidate first.
