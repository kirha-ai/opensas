data site1;
  length usubjid $4;
  input usubjid $ n;
  datalines;
S01 1
S02 2
;
run;
data site2;
  length usubjid $4;
  input usubjid $ n;
  datalines;
S03 3
S04 4
;
run;
proc sql;
  create table pooled as select usubjid, n from site1 union all select usubjid, n from site2;
quit;
proc print data=pooled noobs; run;
