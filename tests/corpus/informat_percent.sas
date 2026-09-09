data d;
  input p percent8.;
  datalines;
45%
;
run;
proc print data=d noobs; run;
