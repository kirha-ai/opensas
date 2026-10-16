/* BUG-sqlcasesubquery (GH#19): a `(select …)` inside a CASE arm in the SELECT list
   was never substituted. The raw `(` stopped parser_expr at the inner `select`, so
   evalSpan's `catch return Value.missing` turned the whole arm into a MISSING and the
   step printed plausible-but-WRONG rows to stdout BEFORE the "expected ')'" error
   fired — the worst failure class (D-002/CLIN-failloud), because a reader who looks
   at stdout sees an answer, not a failure.

   SAS 9.4 SQL Procedure Reference is unambiguous that this is legal: a CASE
   expression may be used "anywhere that you can use a column name" (Creating New
   Columns, printed p.33); the CASE entry makes both `when-condition` and
   `result-expression` sql-expressions ("See sql-expression Component on page 401");
   and sql-expression Component (printed p.401) lists "a query expression" among the
   operands. So a subquery IS a legal CASE operand, in the WHEN and in the result.

   This fixture pins ALL FOUR broken SELECT-list shapes (uncorrelated WHEN,
   correlated WHEN, subquery as the THEN/ELSE value, and `select … into:`) plus the
   GROUP BY / remerge / CALCULATED variants of the same item, AND the WHERE-clause
   shapes that were ALREADY correct — the WHERE and SELECT paths share
   substituteSubqueries, so the already-working half is pinned here too and a future
   refactor of the shared pipeline cannot silently regress it (D-021). */

data part;
  length pid $3;
  input pid $ qty;
  datalines;
P01 10
P02 20
P03 30
;
run;

/* the correlated partner: cap matches qty for P01 and P03, differs for P02 */
data lot;
  length pid $3;
  input pid $ cap;
  datalines;
P01 10
P02 99
P03 30
;
run;

/* avg(qty) = 20, min(qty) = 10, max(qty) = 30 — every expected value below
   derives from those three, so a wrong substitution cannot look plausible. */

/* ---- SELECT list, shape 1: UNCORRELATED subquery in the CASE WHEN.
   Was: every row 'under' (the WHEN compared qty against a MISSING). */
proc sql;
  select pid, qty,
    case when qty > (select avg(qty) from part) then 'over' else 'under' end as band
  from part;
quit;

/* ---- SELECT list, shape 2: CORRELATED subquery in the CASE WHEN.
   Was: every row 'differ'. */
proc sql;
  select pid, qty,
    case when qty = (select cap from lot where lot.pid = part.pid)
         then 'match' else 'differ' end as cmp
  from part part;
quit;

/* ---- SELECT list, shape 3: the subquery IS the THEN / ELSE value (and the WHEN).
   Was: a missing in every cell. */
proc sql;
  select pid, qty,
    case when qty > (select avg(qty) from part)
         then (select max(qty) from part)
         else (select min(qty) from part) end as pick
  from part;
quit;

/* ---- SELECT list, shape 4: `select … into:`. ORDER BY puts qty=30 first, and INTO
   without SEPARATED BY takes the FIRST row (SQL Procedure Reference, "Creating Macro
   Variables from the First Row of a Query Result", printed p.166), so the correct
   answer is 'over' — distinct from the 'under' the broken path produced, which is why
   the rows are ordered rather than left in input order. The wrong value was BOUND
   into the macro symbol table and survived the step error. */
proc sql;
  select case when qty > (select avg(qty) from part) then 'over' else 'under' end
    into :band
  from part order by qty desc;
quit;
proc sql; select "&band" as into_band length=5 from part(obs=1); quit;

/* ---- same item under GROUP BY: the subquery must be collapsed BEFORE this query's
   aggregates are substituted, or substituteAggs folds the SUBQUERY's own avg(qty)
   over the OUTER group and leaves `(select 20 from part)` — a >1-row scalar error.
   grp=0 is P01 alone (max 10, not > 20 -> 'lo'); grp=1 is P02/P03 (max 30 -> 'hi'). */
data part2; set part; grp = (qty > 15); run;
proc sql;
  select grp,
    case when max(qty) > (select avg(qty) from part) then 'hi' else 'lo' end as f
  from part2 group by grp;
quit;

/* ---- and in a REMERGE (an aggregate in the CASE, no GROUP BY): the subquery binds
   this row, so it cannot be pre-substituted per group. max(qty) over the table is 30. */
proc sql;
  select pid, qty,
    case when qty > (select avg(qty) from part) then max(qty) else 0 end as f
  from part;
quit;

/* ---- CALCULATED in WHERE over such an item: bindComputed evaluates the SELECT item
   to bind it, and it used to bind the fabricated MISSING, so the filter ran against a
   value that was never computed. Only P03 is 'over'. */
proc sql;
  select pid,
    case when qty > (select avg(qty) from part) then 'over' else 'under' end as band
  from part where calculated band = 'over';
quit;

/* ================= the WHERE-clause half: ALREADY CORRECT, pinned anyway ========= */

/* WHERE, uncorrelated subquery in the CASE WHEN -> P03 only */
proc sql;
  select pid, qty from part
  where case when qty > (select avg(qty) from part) then 1 else 0 end = 1;
quit;

/* WHERE, correlated subquery in the CASE WHEN -> P01 and P03 */
proc sql;
  select pid, qty from part part
  where case when qty = (select cap from lot where lot.pid = part.pid) then 1 else 0 end = 1;
quit;

/* WHERE, subquery as the CASE THEN value -> qty > 15 picks P02/P03, whose THEN is
   max(qty) = 30, so both match; P01 takes the ELSE 0 and drops out. */
proc sql;
  select pid, qty from part
  where case when qty > 15 then (select max(qty) from part) else 0 end = 30;
quit;

/* HAVING, same shape -> the group whose max exceeds the table average */
proc sql;
  select grp, max(qty) as mx from part2 group by grp
  having case when max(qty) > (select avg(qty) from part) then 1 else 0 end = 1;
quit;
