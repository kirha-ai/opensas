data ae;
  length aesev $8;
  input aesev $ @@;
  datalines;
MILD MILD MILD MODERATE MODERATE SEVERE
;
run;
proc freq data=ae; tables aesev; run;
