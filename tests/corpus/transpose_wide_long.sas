data vs;
  length usubjid $4;
  input usubjid $ week0 week4 week8;
  datalines;
S01 120 118 115
S02 130 128 125
;
run;
proc transpose data=vs out=long(rename=(col1=sbp _name_=visit));
  by usubjid;
  var week0 week4 week8;
run;
proc print data=long noobs; run;
