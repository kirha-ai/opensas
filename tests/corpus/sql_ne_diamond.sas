/* GAP-sqllegacycmp: in PROC SQL the `<>` symbol is NOT EQUAL (Language Reference: Concepts p.219
   Table 11.3 lists `^= ~= ¬= <>` together as the NE spellings), never the
   DATA-step MAX operator. Every parser call in sql.zig runs WITHOUT the
   `where_ctx` flag that applies the WHERE-clause operator rules, so `<>`
   reached the expression parser as MAX: `where x <> 3` computed max(x, 3),
   which is non-zero for EVERY row, and the filter silently kept the whole
   table. That is the BUG-wherene failure mode, in SQL, undetected.

   This fixture pins `<>` = NE in each clause that reaches the parser by a
   different route — WHERE, HAVING, a join ON, a CASE arm and a SELECT item —
   and checks each one against the mnemonic NE, which never had the bug. The
   DATA step is unaffected: there `<>` is still MAX (where_minmax pins that).

   The legacy `=<` / `=>` spellings and `><` are LOUD in PROC SQL (Language Reference: Concepts p.127
   Table 6.4 fn.2/3); those arms are captured-diagnostics tests in sql.zig,
   since a step ERROR would syntax-check-skip the rest of this file. */
data t;
  input x k $;
  datalines;
1 a
3 b
5 c
;
run;

data u;
  input k $ tag $;
  datalines;
a keep
b drop
c keep
;
run;

proc sql;
  /* WHERE: 1 and 5, not all three */
  select x from t where x <> 3;
  /* the same predicate spelled NE — must agree row for row */
  select x from t where x ne 3;
  /* compound: both operands filter */
  select x from t where x <> 3 and x <> 5;
  /* HAVING over a group */
  select k, sum(x) as s from t group by k having sum(x) <> 3;
  /* join ON: the anti-match half of an equijoin */
  select t.x, u.tag from t, u where t.k = u.k and u.tag <> 'drop';
  /* CASE arm and a SELECT-item boolean */
  select x, case when x <> 3 then 'off' else 'on' end as st, (x <> 3) as flag from t;
quit;

/* the DATA step keeps the MAX meaning — `<>` is only NE in a WHERE-style
   context, which is what makes the SQL leak a real difference */
data _null_;
  m = 2 <> 7;
  put m=;
run;
