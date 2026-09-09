data scr;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S02
S03
;
run;
data enr;
  length usubjid $4;
  input usubjid $;
  datalines;
S02
S03
S04
;
run;
proc sql;
  create table allsubj as select usubjid from scr union select usubjid from enr;
quit;
proc print data=allsubj noobs; run;
