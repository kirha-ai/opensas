/* QA tick357 — BUG-sqlselectlength (ee097ef0) added `applyLens`, which
   TRUNCATES char cells IN PLACE on the Result rows. Result rows are built from
   the source dataset's cells, so the hazard this pins is aliasing: a
   `length=` on a SELECT item must shorten the RESULT only and must never reach
   back and shorten the SOURCE table (the D-001 shared-writer failure class —
   scope a behavior change to the caller, never the shared storage).

   Also pinned: the SELECT-clause `length=` and the `char(n)` DDL width must
   agree, since the landing describes the former as the latter applied to the
   SELECT clause (GAP-sqldatatypewidth). */
data lv;
  length s $6;
  s = "abcdef"; output;
  s = "zzyyxx"; output;
run;

/* 1. bare SELECT with length= — the printed result truncates */
proc sql;
  select s length=3 from lv;
quit;

/* 2. …and the SOURCE is untouched, at full width, immediately after */
proc print data=lv noobs; run;

/* 3. a SECOND unmodified select of the same column still sees 6 bytes — proves
      the truncation did not persist into the table the first select read */
proc sql;
  select s from lv;
quit;

/* 4. CREATE TABLE AS: the descriptor Len AND the stored cells must BOTH be 3.
      A descriptor that says 3 over a cell holding 6 bytes is the silent-wrong
      shape this checks for. */
proc sql;
  create table q as select s length=3 from lv;
quit;
proc contents data=q; run;
proc print data=q noobs; run;
data chk;
  set q;
  n = length(s);
run;
proc print data=chk noobs; run;

/* 5. the DDL char(3) twin, for the agreement claim */
proc sql;
  create table r (s char(3));
  insert into r values('abcdef');
quit;
proc print data=r noobs; run;

/* 6. source still intact at the very end */
proc print data=lv noobs; run;
