/* Only one row level is present, so Fisher inference is unavailable. */
options nodate nonumber;
data sample;
  input r c;
  datalines;
0 0
0 1
;
run;
proc freq data=sample;
  tables r*c / fisher;
run;
