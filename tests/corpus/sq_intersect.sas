data safety;
  length usubjid $4;
  input usubjid $;
  datalines;
S01
S02
S03
S04
;
run;
data efficacy;
  length usubjid $4;
  input usubjid $;
  datalines;
S02
S04
S05
;
run;
proc sql;
  create table both as select usubjid from safety intersect select usubjid from efficacy;
quit;
proc print data=both noobs; run;
