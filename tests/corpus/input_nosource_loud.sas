/* BUG-inputnosourcefabricates (D-002): `data d; input x y; run;` with NO INFILE
   and NO DATALINES at all silently fabricated ONE all-missing observation and
   exited 0. Every sibling missing-source is loud (`set nosuchds`,
   `infile 'nosuch.txt'`, an unknown fileref) — this one now is too:
   "ERROR: No DATALINES or INFILE statement." (stderr), the step stops, no data
   set is produced, and later steps are skipped (step-error syntax-check mode).
   stdout below pins exactly that: the step before runs, nothing after the bad
   step prints.
   expect-rc: 1 */
data _null_;
  put "BEFORE: runs";
run;

data d;
  input x y;
run;

proc print data=d; run;

data _null_;
  put "AFTER: must not print";
run;
