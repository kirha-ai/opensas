/* BUG-emptycols: a 0-row dataset must keep its columns (SAS defines the output
   schema at compile time). PROC PRINT shows the headers, PROC SORT + BY and a
   downstream SET..BY run clean on the empty dataset instead of erroring. */
data e;
  input k v $;
  if 0;
  datalines;
;
run;
proc print data=e; run;
proc sort data=e out=s; by k; run;
data _null_;
  set s;
  by k;
  put "row " k= v=;
run;
proc print data=s; run;
