/* BUG-sqlcharaggtype (GH#34) — MIN/MAX over a CHARACTER expression must type
   the result column Char, not Num.

     create table u as
       select g, max(case when x > 3 then '9' else '10' end) as lvl
       from t group by g;

   CONTENTS said `lvl Num 8` while the folded CELL stayed character. The value
   was already collating-correct (computeAggExpr compares through cmpVal, and a
   plain char COLUMN argument kept its type — sql_charagg.sas pins that), so
   only the descriptor lied, which is exactly the failure class a green listing
   hides: PROC SQL prints the cell, but a DATA step `set` of the table read the
   text as numeric MISSING — '9' silently destroyed, the same damage
   BUG-sqlremergecharcol did to computed columns.

   Doc evidence (SQL Procedure Reference): the CASE-WHEN section's own example
   (~p.363) puts string literals in the arms and "create[s] a character column";
   Table 2.6 states no numeric restriction for MAX/MIN — the summary functions
   accept a character argument and return its value, so the result column
   carries the argument's type.

   Two halves make the type right, mirroring how a bare CASE item is typed:
     a pure CASE argument is typed statically from its first THEN literal
     (caseResultType — this survives a zero-row result, where no value exists);
     any other char expression has no static typer, so retypeComputed corrects
     the column from the folded value, the same evidence a computed column
     gets (BUG-sqlremergecharcol).

   NOT this bug's scope: the DATA-step FUNCTION form `max('9','10')` still
   coerces to numeric — that half of GH#34 is [needs-oracle] (functions-ref
   MAX/MIN say "numeric constant, variable, or expression"; no char/collating
   statement in-tree), and this fixture deliberately probes only the SQL
   aggregate form.

   No width is invented for the result column (DOC-SILENT, BUG-sqlcolwidthloss):
   Len stays the data-derived widest value, unchanged from a computed column. */

data t;
  input g $ x;
  datalines;
A 1
A 5
B 2
B 9
;
run;

/* ── the reported shape: GROUP BY, char CASE, create table ─────────────── */
proc sql;
  create table u as
    select g, max(case when x > 3 then '9' else '10' end) as lvl
    from t group by g;
quit;
proc contents data=u; run;
data _null_; set u;
  length ty $1;
  ty = vtype(lvl);
  put 'SET g=' g 'lvl=[' lvl ']';        /* char cell survives a set */
  put 'SET vtype(lvl)=' ty;              /* C — was N before the fix */
run;

/* ── min() too, and the collating values both ways ─────────────────────── */
proc sql;
  create table lohi as
    select g,
           min(case when x > 3 then '9' else '10' end) as lo,
           max(case when x > 3 then '9' else '10' end) as hi
    from t group by g;
quit;
proc contents data=lohi; run;

/* ── CONTROL: a NUMERIC CASE stays Num ─────────────────────────────────── */
proc sql;
  create table ncase as
    select g, max(case when x > 3 then 9 else 10 end) as nlvl
    from t group by g;
quit;
proc contents data=ncase; run;

/* ── CONTROL: a plain char COLUMN argument keeps its type (also pinned by
   sql_charagg.sas; here at the CONTENTS level, not just the listing) ───── */
proc sql;
  create table plaincol as select max(g) as mg, min(g) as mng from t;
quit;
proc contents data=plaincol; run;

/* ── a NON-CASE char expression: no static type, value-corrected ───────── */
proc sql;
  create table cexpr as select g, max('z' || g) as zc from t group by g;
quit;
proc contents data=cexpr; run;

/* ── remerge path: the aggregate broadcast beside a detail column ──────── */
proc sql;
  create table remr as
    select g, x, max(case when x > 3 then '9' else '10' end) as lvl
    from t group by g;
quit;
proc contents data=remr; run;

/* ── zero-row result: nothing to learn from a value; the static CASE guess
   stands (lvl Char even with Observations 0) ───────────────────────────── */
proc sql;
  create table empty as
    select g, max(case when x > 3 then '9' else '10' end) as lvl
    from t where x > 100 group by g;
quit;
proc contents data=empty; run;

/* ── the downstream symptom: a nested SELECT over the mistyped column used
   to re-render the text BEST12 (lengthc 12); it keeps the char width now ── */
proc sql;
  select g, lvl, lengthc(lvl) as w from u;
quit;
