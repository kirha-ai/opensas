/* DS: derive completion flag, tabulate (DATA step derive + PROC FREQ) */
data ds;
  input USUBJID $ DSDECOD : $9.;
  datalines;
01-001 COMPLETED
01-002 COMPLETED
01-003 WITHDREW
01-004 COMPLETED
01-005 WITHDREW
;
run;

data ds2;
  set ds;
  compl = (DSDECOD = "COMPLETED");
run;

proc freq data=ds2;
  tables compl;
run;
