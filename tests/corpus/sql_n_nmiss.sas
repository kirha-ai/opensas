data lb;
  length usubjid $4 param $4;
  input usubjid $ param $ aval;
  datalines;
S01 ALT 10
S02 ALT .
S03 ALT 30
S04 ALT .
S01 AST 5
S02 AST 15
;
run;
proc sql;
  /* whole-column: 6 rows, 4 non-missing, 2 missing */
  create table overall as select n(aval) as n_val, nmiss(aval) as n_miss, count(*) as n_rows from lb;
  /* per-param */
  create table byparam as select param, n(aval) as n_val, nmiss(aval) as n_miss from lb group by param;
quit;
proc print data=overall noobs; run;
proc print data=byparam noobs; run;
