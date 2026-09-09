data vs;
  length usubjid $4;
  input usubjid $ v1 v2;
  datalines;
S01 120 80
S02 130 85
;
run;
proc datasets library=work nolist;
  modify vs;
    rename v1=sysbp v2=diabp;
quit;
proc print data=vs noobs; run;
