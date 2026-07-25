# T-SQL Anti-Patterns in Azure SQL

The fastest wins usually come from removing patterns that defeat indexes or force
row-by-row work. Each item below: the anti-pattern, why it hurts, and the fix.

## 1. Non-SARGable predicates

A predicate is **SARGable** (Search ARGument-able) when the optimizer can seek an
index on the column. Wrapping the **column** in a function or expression breaks that.

```sql
-- ❌ Function on the column -> index scan
WHERE YEAR(o.OrderDate) = 2024
WHERE CONVERT(date, o.OrderDate) = '2024-01-01'
WHERE UPPER(c.Email) = 'A@B.COM'
WHERE o.Total * 1.1 > 100

-- ✅ Rewrite so the column is bare -> index seek
WHERE o.OrderDate >= '2024-01-01' AND o.OrderDate < '2025-01-01'
WHERE o.OrderDate >= '2024-01-01' AND o.OrderDate < '2024-01-02'
WHERE c.Email = 'a@b.com'          -- store normalized, or use a computed/persisted col
WHERE o.Total > 100 / 1.1
```

For case-insensitive matching, rely on the column's collation (Azure SQL default
collations are case-insensitive) instead of `UPPER`/`LOWER`.

## 2. Implicit conversion (the silent index killer)

A data-type mismatch forces `CONVERT_IMPLICIT` and usually a scan. The classic in
Azure SQL apps: an ORM sends an **`NVARCHAR`** parameter against a **`VARCHAR`**
column. The whole column gets converted.

```sql
-- ❌ @p is NVARCHAR, Email is VARCHAR -> CONVERT_IMPLICIT(Email) scan
WHERE c.Email = @p

-- ✅ Match the type at the source
--   .NET: new SqlParameter("@p", SqlDbType.VarChar)   (or DbType.AnsiString)
--   EF Core: configure the column with .IsUnicode(false) / use varchar
```

Look for the conversion warning on the operator in the actual plan (see
`execution-plans.md`). Fix the **type**, not the query shape.

## 3. SELECT *

```sql
-- ❌ Forces key lookups, defeats covering indexes, ships unused bytes
SELECT * FROM dbo.Orders WHERE CustomerId = @id;

-- ✅ Project only what you need; lets a covering index satisfy the query
SELECT OrderId, OrderDate, Total FROM dbo.Orders WHERE CustomerId = @id;
```

## 4. Parameter sniffing regressions

One cached plan compiled for an atypical parameter value hurts everyone else.
Symptoms: same proc is fast sometimes, slow others; plan in cache fits the "wrong"
row count. **First confirm it in Query Store** (one `query_id`, multiple plans, wide
CPU/duration/reads spread), then climb this ladder **in order, least to most invasive —
stop at the first rung that fixes it:**

1. **Compatibility level 160 (PSP optimization)** — **Parameter Sensitive Plan**
   optimization keeps multiple plans for one query on skewed data; often removes the need
   for `RECOMPILE` workarounds. Test via Query Store, keep FORCE_LAST_GOOD_PLAN on (`iqp.md`).
2. **Query Store hint** — inject `RECOMPILE` or `OPTIMIZE FOR` by `query_id` via
   `sys.sp_query_store_set_hints`, **no code change/redeploy** (`query-store.md`).
3. **In-code hint** — `OPTION (RECOMPILE)`, `OPTION (OPTIMIZE FOR (@p = <typical>))`,
   or `OPTION (OPTIMIZE FOR UNKNOWN)` on the one statement (requires a deploy).
4. **LAST RESORT — `ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF;`**
   This is a **blunt, database-wide** switch that forces average-density guesses for
   *every* query and can regress others — never reach for it first; use it only after
   rungs 1–3 are ruled out, and prefer scoping it to a single query instead.

> If someone proposes `PARAMETER_SNIFFING = OFF` as the opening move, walk them back **up**
> the ladder: it's rung 4, the last resort — start at rung 1 (or a Query Store hint for an
> immediate, scoped mitigation) and target the one hot statement, not the whole database.

## 5. Scalar user-defined functions (UDFs)

Scalar UDFs historically execute **per row** and serialize the plan.

```sql
-- ❌ Scalar UDF called for every row
SELECT o.OrderId, dbo.fn_FormatTotal(o.Total) FROM dbo.Orders AS o;
```

- At **compat level 150+**, **Scalar UDF Inlining** transforms many scalar UDFs
  into set-based expressions automatically (see `iqp.md`). Verify yours inlines
  (`sys.sql_modules.is_inlineable`).
- Otherwise, rewrite as an **inline table-valued function** and `CROSS APPLY`, or
  inline the expression.

## 6. Multi-statement TVFs (MSTVFs) for large sets

MSTVFs carry a fixed cardinality guess (100 rows). Prefer **inline TVFs**.
Interleaved execution (compat 140+) mitigates but doesn't eliminate the issue.

## 7. Row-by-row processing (RBAR)

Cursors and `WHILE` loops that issue one statement per row. Replace with a single
set-based statement, or batch updates/deletes in chunks for very large tables.

```sql
-- ✅ Set-based
UPDATE o SET o.Status = 'Closed'
FROM dbo.Orders AS o
WHERE o.ShippedDate < '2024-01-01';

-- ✅ Chunked for huge tables (avoids long log/lock)
WHILE 1 = 1
BEGIN
    DELETE TOP (5000) FROM dbo.Audit WHERE CreatedAt < '2023-01-01';
    IF @@ROWCOUNT = 0 BREAK;
END
```

## 8. OR across different columns

`WHERE A = @a OR B = @b` often can't use either index efficiently.

```sql
-- ✅ Split into index-friendly branches
SELECT ... WHERE A = @a
UNION
SELECT ... WHERE B = @b;
```

## 9. Deep OFFSET pagination

`OFFSET 100000 ROWS` re-reads everything skipped. Use **keyset / seek** pagination.

```sql
-- ❌ Slows linearly with page depth
ORDER BY OrderDate DESC OFFSET @n ROWS FETCH NEXT 20 ROWS ONLY;

-- ✅ Keyset pagination on an indexed key
WHERE (OrderDate, OrderId) < (@lastDate, @lastId)
ORDER BY OrderDate DESC, OrderId DESC OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
```

## 10. NOLOCK as a "performance" fix

`WITH (NOLOCK)` / `READ UNCOMMITTED` returns dirty/duplicated/missing rows. It's a
correctness hazard, not a tuning tool. In Azure SQL Database,
`READ_COMMITTED_SNAPSHOT` is **ON by default**, so readers already don't block
writers — fix the underlying query/index instead.

## 11. Large literal IN-lists / non-parameterized SQL

Thousands of distinct literal queries bloat the plan cache and cause CPU on
compiles. Parameterize, pass a **table-valued parameter (TVP)**, or use
`STRING_SPLIT`/JSON to join against a set.
