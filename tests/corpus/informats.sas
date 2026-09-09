data _null_;
  input n :comma8. d :date9.;
  put "n=" n;
  put "d=" d;
  datalines;
1,234 01JAN1960
;
run;
