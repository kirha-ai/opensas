data randomized;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S02
S03
S04
;
run;
data completed;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S03
;
run;
proc sql;
  create table discontinued as select usubjid from randomized except select usubjid from completed;
quit;
proc print data=discontinued noobs; run;
