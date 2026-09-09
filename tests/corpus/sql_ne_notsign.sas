/* BUG-sqlnotequalunicode: `¬=` (U+00AC NOT SIGN + `=`, bytes 0xC2 0xAC 0x3D)
   is a NOT-EQUAL spelling — Language Reference: Concepts p.219 Table 11.3 lists `^= ~= ¬= <>`
   together as the NE spellings; SQL Procedure User's Guide Table 8.2 group 7
   (printed p.403-404) lists `¬=, ^=, <>, ne`. The lexer advanced ONE byte at a
   time, so the two-byte `¬` split from its `=`: `x ¬= 3` lexed as `x ¬ = 3`
   (NOT then EQ) — LOUD in the DATA step, but in PROC SQL the predicate
   silently degraded and KEPT EVERY ROW at exit 0 (the BUG-wherene / 295181bb
   `<>` failure mode, second instance). Maximal munch in the lexer now makes
   `¬=` ONE .ne token, so both surfaces share the existing NE path by
   construction; `¬` alone stays NOT and `¬ =` (space) stays NOT-then-EQ.

   This fixture pins EVERY Table 8.2 / Table 11.3 not-equal spelling agreeing
   row-for-row across PROC SQL and the DATA step, side by side, so the two
   surfaces can never silently diverge on an NE spelling again. Each query
   must return 1 and 5 (not 3, not all three). The DATA-step IF is included
   for every spelling except `<>`: outside a WHERE-style context `<>` is the
   MAX operator by design (pinned by sql_ne_diamond / where_minmax). */

data t;
  input x k $;
  datalines;
1 a
3 b
5 c
;
run;

proc sql;
  /* each spelling in a SQL WHERE — all five must agree */
  select x from t where x ¬= 3;
  select x from t where x ^= 3;
  select x from t where x ~= 3;
  select x from t where x <> 3;
  select x from t where x ne 3;
  /* the new token rides the existing NE path through every clause route:
     HAVING, a join ON, a CASE arm (the routes 295181bb pinned for <>) */
  select k, sum(x) as s from t group by k having sum(x) ¬= 3;
  select x, case when x ¬= 3 then 'off' else 'on' end as st from t;
  /* maximal munch must not eat the NOT: `¬(x = 3)` still negates */
  select x from t where ¬(x = 3);
quit;

/* the DATA-step WHERE agrees with every spelling, side by side with SQL */
data _null_; set t; where x ¬= 3; put 'data-where notsign ' x=; run;
data _null_; set t; where x ^= 3; put 'data-where caret    ' x=; run;
data _null_; set t; where x ~= 3; put 'data-where tilde    ' x=; run;
data _null_; set t; where x <> 3; put 'data-where diamond  ' x=; run;
data _null_; set t; where x ne 3; put 'data-where mnemonic ' x=; run;

/* the IF agrees for the spellings that are NE there (`<>` is MAX in an IF) */
data _null_; set t; if x ¬= 3; put 'data-if notsign ' x=; run;
data _null_; set t; if x ^= 3; put 'data-if caret    ' x=; run;
data _null_; set t; if x ~= 3; put 'data-if tilde    ' x=; run;
data _null_; set t; if x ne 3; put 'data-if mnemonic ' x=; run;
