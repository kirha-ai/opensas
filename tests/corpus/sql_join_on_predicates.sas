/* BUG-sqlonpredicates (GH#18) — a JOIN's ON span never went through
   desugarPredicates, so every SQL-only predicate in it was SILENTLY WRONG AT
   RC 0, in both directions at once:

     on a.x between b.lo and b.hi   -> 6 rows (the whole cartesian product)
     on b.nm like 'a%'              -> 0 rows
     on b.nm contains 'ab'          -> 0 rows
     on b.nm is not null            -> 0 rows

   Cause: `pe.Parser.parseExpr` consumes exactly one expression and leaves the
   cursor on the first token it cannot use, WITHOUT reporting that it stopped.
   `a.x between b.lo and b.hi` therefore collapsed to a bare `a.x` — and a bare
   column reference is always truthy, so the ON matched every pair. The LIKE /
   CONTAINS / IS NOT NULL spellings collapsed to a bare `b.nm` whose first
   character is non-numeric, i.e. always falsy, so they matched nothing.

   `ON sql-expression` is the SAME grammar as WHERE and HAVING:
     - joined-table Component, SQL Procedure Components printed p.373 / pdf 389:
       "table-name-1 <<AS> alias-1> <INNER> JOIN table-name-2 <<AS> alias-2>
        ON sql-expression".
     - IS Operator, printed p.372 / pdf 388: "IS NULL and IS MISSING are
       predicates that test for a missing value. IS NULL and IS MISSING are used
       in the WHERE, ON, and HAVING expressions."
     - Table 8.2 "Operators and Order of Evaluation", printed p.403-404 / pdf
       419, lists <NOT> BETWEEN, <NOT> CONTAINS, <NOT> IN, IS <NOT> and <NOT>
       LIKE in group 6 of sql-expression, above the group-7 comparisons.
   So ON now runs the ONE shared desugarPredicates the other eight sites use.

   This fixture pins the ROW SETS, not just the headline BETWEEN count — the
   already-correct cases (IN/NOT IN, the six comparison operators, and the
   `col = col` equi-join hash fast path) are pinned here too so a future change
   to the join pipeline cannot regress them silently. Invented data (D-011). */

data a;
  do x = 1, 5, 9; output; end;
run;

data b;
  length nm $5;
  lo = 0; hi = 3; nm = 'abc'; output;
  lo = 4; hi = 6; nm = 'xyz'; output;
run;

/* b2 exists only so the equi-join cases are NOT vacuous: a.x never equals any
   b.lo, so `on a.x = b.lo` returns zero rows there and would pass even if the
   fast path were broken. Every b2.lo matches an a.x. */
data b2;
  length nm $5;
  lo = 1; hi = 3; nm = 'abc'; output;
  lo = 5; hi = 6; nm = 'xyz'; output;
  lo = 9; hi = 9; nm = 'a';   output;
run;

/* ── group 6: the predicates the bug ate ─────────────────────────────── */
proc sql;
  title 'between';        select a.x, b.lo, b.hi from a join b on a.x between b.lo and b.hi;
  title 'notbetween';     select a.x, b.lo, b.hi from a join b on a.x not between b.lo and b.hi;
  title 'like';           select a.x, b.nm from a join b on b.nm like 'a%';
  title 'notlike';        select a.x, b.nm from a join b on b.nm not like 'a%';
  title 'notparenlike';   select a.x, b.nm from a join b on not (b.nm like 'a%');
  title 'contains';       select a.x, b.nm from a join b on b.nm contains 'ab';
  title 'notcontains';    select a.x, b.nm from a join b on b.nm not contains 'ab';
  title 'isnull';         select a.x, b.nm from a join b on b.nm is null;
  title 'isnotnull';      select a.x, b.nm from a join b on b.nm is not null;
  title 'ismissing';      select a.x, b.nm from a join b on b.nm is missing;
  title 'isnotmissing';   select a.x, b.nm from a join b on b.nm is not missing;
quit;

/* ── already correct — pinned against regression ─────────────────────── */
proc sql;
  /* ponytail: a MULTI-element `in ('abc', 'zzz')` in an ON is refused upstream
     of the predicate path ("UNSUPPORTED: PROC SQL: unsupported SELECT") because
     the FROM/ON span scan does not keep the parenthesised comma out of the
     SELECT-item split. That reproduces on the pre-fix build too, so it is a
     separate defect, reported rather than pinned here; the single-element form
     exercises the IN desugar this fixture is guarding. */
  title 'in';             select a.x, b.nm from a join b on b.nm in ('abc');
  title 'notin';          select a.x, b.nm from a join b on b.nm not in ('abc');
  title 'eq';             select a.x, b2.lo from a join b2 on a.x = b2.lo;
  title 'necaret';        select a.x, b2.lo from a join b2 on a.x ^= b2.lo;
  title 'neangle';        select a.x, b2.lo from a join b2 on a.x <> b2.lo;
  title 'lt';             select a.x, b2.lo from a join b2 on a.x < b2.lo;
  title 'gt';             select a.x, b2.lo from a join b2 on a.x > b2.lo;
  title 'le';             select a.x, b2.lo from a join b2 on a.x <= b2.lo;
  title 'ge';             select a.x, b2.lo from a join b2 on a.x >= b2.lo;
quit;

/* ── mixtures: one desugared predicate must not disturb the other half ─ */
proc sql;
  /* an equality AND a desugared predicate: extractEqKeys appends the eq key,
     then rejects the LIKE half, so the whole ON falls back to the nested loop
     and BOTH halves are evaluated. */
  title 'eqandlike';      select a.x, b2.nm from a join b2 on a.x = b2.lo and b2.nm like 'a%';
  title 'betweenandcontains';
                          select a.x, b2.nm from a join b2 on a.x between b2.lo and b2.hi and b2.nm contains 'a';
  title 'likeoreq';       select a.x, b2.nm from a join b2 on b2.nm like 'a%' or a.x = b2.lo;
  /* a LEFT JOIN keeps its unmatched left row with the right side missing even
     when the ON is a desugared predicate. */
  title 'leftbetween';    select a.x, b.lo, b.hi from a left join b on a.x between b.lo and b.hi;
quit;
