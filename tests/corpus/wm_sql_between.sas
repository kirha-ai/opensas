data lb;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 5
S02 18
S03 42
S04 65
S05 90
;
run;
proc sql;
  create table normal as select usubjid, aval from lb where aval between 18 and 65;
quit;
proc print data=normal noobs; run;
