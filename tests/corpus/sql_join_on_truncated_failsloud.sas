/* BUG-sqlonpredicates (GH#18), second half — the DEFECT CLASS, not one operator.

   `pe.Parser.parseExpr` consumes exactly one expression and, by its documented
   contract, leaves the cursor on the first token it could not use. It never
   reports that it stopped early. So any ON predicate whose TAIL uses an
   operator opensas does not implement was silently TRUNCATED to its parsable
   head — and a bare column reference as the whole condition is always truthy,
   which is how `on a.x between b.lo and b.hi` became the full cartesian product
   at rc 0. Desugaring BETWEEN/LIKE/CONTAINS/IS NULL fixes the four operators we
   know about; refusing the leftover tail fixes the next one.

   The probe here is the `?` spelling of CONTAINS, which opensas does not
   implement. It is unambiguously legal SAS — SQL Procedure Components,
   "CONTAINS Operator", printed p.370 / pdf 386: "Tests whether a string is part
   of a column's value. Alias: ?" (the Language Reference: Concepts calls it
   "the CONTAINS (?) operator" for the DATA-step WHERE). `?` lexes as a token
   the expression parser cannot consume, so it used to leave `b.nm` alone as the
   condition: zero rows, rc 0, no complaint.

   rc 2, not 1: a legal-SAS operator we have not implemented is an opensas GAP,
   and D-009b(i) settles that "real SAS runs this clean" does not downgrade one.
   expect-rc: 2

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
  /* the gap: refused loudly, naming the token it could not consume, instead of
     evaluating a truncated `on b.nm` and printing a wrong (here empty) table. */
  title 'contains_alias';
  select a.x, b.nm from a join b on b.nm ? 'ab';
quit;
