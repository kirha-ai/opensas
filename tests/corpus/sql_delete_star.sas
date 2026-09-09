/* #61: SAS 9.4 leniently ignores a stray '*' in PROC SQL DELETE and executes it. */
data w;
  input id v;
  datalines;
1 .
2 5
3 .
;
run;

proc sql;
  delete * from w where v is null;   /* deletes id 1 & 3 */
quit;

data _null_;
  set w end=e;
  n+1;
  if e then put "rows_remaining=" n;
run;
