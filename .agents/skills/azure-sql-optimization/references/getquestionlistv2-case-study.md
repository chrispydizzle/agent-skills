# Case Study: Optimizing a Hot Dynamic Stored Procedure

This case study distills the `GetQuestionListV2` / `BuildQuestionListV2`
optimization work from Q&A. Use it when an Azure SQL OLTP procedure builds
dynamic SQL, supports multiple filters/sorts, and serves both normal shallow-page
traffic and abusive deep-pagination traffic.

## The durable workflow

1. **Trace the true entry-point contract.** Follow API parameters into wrapper
   sprocs and builder sprocs before benchmarking. In this case
   `GetQuestionListV2` converted `@Page/@PageSize` into a **row offset**:
   `@Offset = (@Page - 1) * @PageSize`, then passed `@Rows = @PageSize`.
2. **Benchmark a matrix, not one happy path.** Capture actual plans and
   `STATISTICS IO/TIME` across:
   - sort modes (`UpdatedAt`, `CreatedAt`, `AnswerCount`)
   - filters (`all`, `resolved`, `unresolved`, `aiansweronly`, `noanswers`)
   - page depths (page 1, mid-page, scraper-tail pages)
   - before/after object states
3. **Use controls.** Include dominant paths expected not to change. The Q&A work
   explicitly proved the dominant `UpdatedAt` path stayed byte-identical while the
   targeted paths improved.
4. **Verify correctness with counts.** Every rewritten count path must return
   byte-identical totals before reading the perf result as a win.
5. **Restore and re-check shared environments.** In shared INT/test databases,
   deployments can clobber experimental objects. Verify live object definitions,
   indexes, and `modify_date`, not just source files.

## Indexed-view lessons

Indexed views can be the right fix when the proc repeatedly computes the same hot
aggregate or sort key, but they move work to the write path.

- Keep the view grain aligned with the query. The successful Q&A shape made
  `QuestionAnswerCountV2` carry the columns the proc needed (`Locale`,
  `AnswerCount`, resolution flags) so the proc could seek and avoid redundant
  joins.
- Put nonclustered indexed-view index DDL next to the view definition when that is
  the repository convention, and register any new SQL file in the project file if
  the SQL project uses explicit includes.
- Use the indexed-view SET options for deploy/probe scripts.
- `ONLINE = ON` was valid for a nonclustered index build over a schemabound
  indexed view in Azure SQL, but it only changes build-time blocking. It does not
  reduce steady-state indexed-view maintenance cost or deadlock risk.
- Be careful with optimizer indexed-view auto-matching. A before/after plan can
  read a different indexed view than the SQL text names, which can make A/B
  results look contradictory until the actual plan object references are checked.

## Sort elimination by matching the index order

The original `AnswerCount` path joined the whole locale partition and sorted it
before `TOP/OFFSET` could return a page. Reads were flat across page depths
because every page paid the whole-partition sort cost.

The winning shape was a preordered indexed-view access path:

```sql
CREATE NONCLUSTERED INDEX QAC2_IDX_LocaleAnswerCountQuestionId
ON dbo.QuestionAnswerCountV2 (Locale, AnswerCount DESC, QuestionId DESC)
INCLUDE (HasAcceptedAnswer, HasRecommendedAnswer, NonAiAnswerCount);
```

Key observations:

- The sort disappeared; reads changed from a flat whole-partition floor to a
  small `offset + rows`-bounded range scan.
- Including the resolution flags let `resolved` / `unresolved` stay covered.
- `QuestionId DESC` provided a deterministic tiebreaker and avoided unstable
  pagination when many rows shared the same sort value.
- The win was V2-only because V1 referenced a different answer-count view.

For the `CreatedAt` path, the useful index lived on the shared
`QuestionLastActivityLocaleCount` view, so both V1 and V2 benefited:

```sql
CREATE NONCLUSTERED INDEX QLA_IDX_LocaleCreatedAtUpdatedAt_I_QuestionId
ON dbo.QuestionLastActivityLocaleCount
    (Locale, QuestionCreatedAt DESC, UpdatedAt DESC)
INCLUDE (QuestionId);
```

The important detail is the secondary `UpdatedAt DESC` key. It matched the proc's
full `ORDER BY` and avoided a residual sort; indexing only
`Locale, QuestionCreatedAt` left the engine with more work.

## Count-path rewrites

Filtered count queries often have different best shapes than list queries.

- If the view now carries `Locale`, filter `qac.Locale` directly instead of
  joining back to another locale view just to prove existence. In the Q&A case,
  the join removed zero rows and only forced scans.
- Create indexes for the exact resolution predicate shape. A seekable index on
  `(Locale, HasAcceptedAnswer, HasRecommendedAnswer, NonAiAnswerCount)` changed
  sparse AI-answer counts from full-view scans to targeted seeks.
- Avoid broad `OR` predicates when each branch can seek. `resolved` counted faster
  as `UNION ALL` over "accepted" plus "recommended but not accepted" branches.
- Replace anti-joins carefully. For `noanswers`, using
  `locale total - answered total` was cheaper than probing for absence row by row,
  but still had to count two large locale slices; validate the exact semantics.
- For tag-filtered counts, build the tag candidate set first, then join to the
  seekable aggregate/indexed view using the narrow resolution keys.

## Hints, row goals, and parameter sniffing

The Q&A tuning initially suggested `DISABLE_OPTIMIZER_ROWGOAL` might be protecting
deep pages from nested-loop blowups. That was only true in a contaminated test
where a shallow-page plan was cached and reused for deep pages.

The verified behavior was:

- **Keep `RECOMPILE`** for dynamic SQL whose optimal shape depends heavily on
  `@Offset`, locale, and filter selectivity.
- **Do not keep `DISABLE_OPTIMIZER_ROWGOAL` by default.** With `RECOMPILE` still
  present, the optimizer chose fast row-goal plans for shallow/dense cases and
  naturally switched to bounded scan shapes for sparse/deep cases.
- Benchmark hint changes with `RECOMPILE` in place and sweep deep pages. Otherwise
  parameter-sniffing artifacts can masquerade as a row-goal problem.
- Remove one hint block at a time. Count and list dynamic-SQL branches can have
  separate hint blocks with different risk profiles.

## Pagination contract checks

When a builder proc receives a row offset, the safe inner prefix is:

```sql
TOP (@Offset + @Rows)
```

The older pattern below treats a row offset like a page number and overfetches:

```sql
TOP ((@Offset + 1) * @Rows)
```

That usually does not break page correctness because the outer `OFFSET/FETCH`
still slices the requested page, but it creates a large deep-page work multiplier.
It can also expose nondeterministic ties if the sort lacks a complete tiebreaker.

## Concurrency and write-path validation

Indexed views are not read-only magic. They are maintained during writes and can
become a contention hotspot.

- Avoid joining extra hot tables into an indexed view unless the query truly needs
  them. A prior `QuestionAnswerOrder` view joined into
  `QuestionLastActivityLocaleCount`; concurrent recommendation/acceptance writes
  then serialized on shared materialized rows and caused deadlocks.
- Validate write-path tests, not only read benchmarks. The final consolidated
  indexed-view shape removed the unnecessary join and eliminated the reproduced
  deadlock signature in stress testing.
- Treat "online index build succeeded" and "steady-state write path is safe" as
  separate claims.

## Acceptance checklist for similar work

- Actual plans captured before and after for each hot branch.
- Logical reads, CPU/duration, and sort/spill presence reported per branch.
- Counts/results byte-identical for every rewritten filter.
- Dominant existing path has an explicit no-regression control.
- Deep-page traffic is included in the matrix, especially when bots/scrapers exist.
- Hints are tested with and without plan-cache contamination.
- Indexed-view write-path/concurrency tests pass.
- Repository deployment wiring is checked: file placement, project includes, and
  live database object definitions.
