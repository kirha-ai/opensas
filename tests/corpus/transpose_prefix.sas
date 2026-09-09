data long;
  length usubjid $4;
  input usubjid $ aval;
  datalines;
S01 10
S01 20
S01 30
S02 40
S02 50
;
run;
proc transpose data=long out=wide prefix=visit;
  by usubjid;
  var aval;
run;
proc print data=wide noobs; run;
