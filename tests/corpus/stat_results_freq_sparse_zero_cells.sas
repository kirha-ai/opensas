/* Persist all zero cells in the cartesian product for a sparse two-way OUT= table. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 3
2 2 2
2 3 1
;
run;

proc freq data=sample noprint;
  weight n;
  tables r*c / sparse out=zerocells;
run;
proc print data=zerocells noobs;
run;
