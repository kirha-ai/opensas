/* BUG-sqlcasesubquery, fail-loud half: the CASE sites that have NO `Library` in
   scope, and therefore cannot run a subquery at all.

   `evalCase` resolves a `(select …)` for every caller that can reach a Library —
   the SELECT list, WHERE and HAVING. Four callers cannot, and each was PROBED
   rather than assumed (D-025): ORDER BY (`orderRows`), a summary-function argument
   (`computeAggExpr`), GROUP BY (`groupKey`) and a CHECK constraint. A `coalesce(case
   …)` SELECT item is NOT among them — it is an `.expr` item, so the row loop
   collapses its subqueries before substituteCoalesce runs, and it answers correctly
   today. Before this fix the four sites did the same damage as the SELECT list:
   parser_expr stopped at the inner `select`, the arm became a MISSING, and a
   plausible wrong answer printed BEFORE the error — an aggregate folded over
   missings, or every row sorted on an identical missing key.

   They are now a GAP: valid SAS 9.4 (sql-expression Component, printed p.401, lists
   "a query expression" as an operand, and the CASE entry makes its arms
   sql-expressions) that opensas does not implement, so rc 2 per D-009/D-009b(i) —
   NEVER rc 1, which would tell the caller to fix correct SAS. Critically the guard
   fires BEFORE the fold / before the sort key loop, not inside it: both of those
   loops swallow the error with `catch Value.missing`, so a guard placed inside them
   would still have printed the wrong row first.

   `nosyntaxcheck` is on so BOTH gap sites run in one program instead of the first
   one errhalting the second away (D-024 — it changes which steps run, never the
   rc). The last step proves the supported site is untouched: the SAME subquery in
   the SELECT list still answers correctly, which is the boundary this fixture
   documents.
   expect-rc: 2 */

options nosyntaxcheck;

data part;
  length pid $3;
  input pid $ qty;
  datalines;
P01 10
P02 20
P03 30
;
run;

/* avg(qty) = 20 */

/* GAP 1 — subquery inside a CASE used as a summary-function ARGUMENT. The correct
   answer is 1 (only P03 exceeds 20); the old path folded three missings and printed
   a confident 0. Nothing may print now. */
proc sql;
  select sum(case when qty > (select avg(qty) from part) then 1 else 0 end) as n
  from part;
quit;

/* GAP 2 — subquery inside a CASE used as an ORDER BY key. The correct order is
   P03, P01, P02; the old path gave every row the same missing key and emitted input
   order, which looks exactly like a legitimate result. Nothing may print now. */
proc sql;
  select pid, qty from part
  order by case when qty > (select avg(qty) from part) then 1 else 2 end, qty;
quit;

/* the SUPPORTED site, unchanged: the same subquery in the SELECT list answers. */
proc sql;
  select pid, case when qty > (select avg(qty) from part) then 'over' else 'under' end as band
  from part;
quit;
