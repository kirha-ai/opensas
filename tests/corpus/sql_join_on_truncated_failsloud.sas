/* BUG-sqlonpredicates (GH#18), second half — the DEFECT CLASS, not one operator.

   `pe.Parser.parseExpr` consumes exactly one expression and, by its documented
   contract, leaves the cursor on the first token it could not use. It never
   reports that it stopped early. So any ON predicate whose TAIL uses an
   operator opensas does not implement was silently TRUNCATED to its parsable
   head — and a bare column reference as the whole condition is always truthy,
   which is how `on a.x between b.lo and b.hi` became the full cartesian product
   at rc 0. Desugaring BETWEEN/LIKE/CONTAINS/IS NULL fixes the four operators we
   know about; refusing the leftover tail fixes the next one.

   The probe here is the `?` spelling of CONTAINS. It is unambiguously legal SAS
   — SQL Procedure Components, "CONTAINS Operator", printed p.370 / pdf 386:
   "Tests whether a string is part of a column's value. Alias: ?" (the Language
   Reference: Concepts calls it "the CONTAINS (?) operator" for the DATA-step
   WHERE). Before GAP-sqlcontainsquestion, `?` lexed as a token the SQL
   expression path could not consume; now it desugars to the same row set as
   spelled-out CONTAINS.

   Invented data (D-011). */

data a;
  do x = 1, 5, 9; output; end;
run;

data b;
  length nm $5;
  nm = 'abc'; output;
  nm = 'xyz'; output;
run;

proc sql;
  /* positive control: the spelled-out operator is implemented and this is the
     row set the `?` arm below must never silently disagree with. */
  title 'contains_word';
  select a.x, b.nm from a join b on b.nm contains 'ab';
quit;

proc sql;
  /* alias: must match the positive control above. */
  title 'contains_alias';
  select a.x, b.nm from a join b on b.nm ? 'ab';
quit;
