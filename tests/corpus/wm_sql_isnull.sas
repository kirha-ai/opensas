data lb;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 5.1
S02 .
S03 7.2
S04 .
;
run;
proc sql;
  create table hasval as select usubjid from lb where aval is not null;
  create table noval as select usubjid from lb where aval is null;
quit;
proc print data=hasval noobs; run;
proc print data=noval noobs; run;
