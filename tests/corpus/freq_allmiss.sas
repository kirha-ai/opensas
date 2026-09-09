/* NOTE-freqallmissnone: PROC FREQ with an all-missing TABLES variable.
   Base SAS 9.4 Procedures Guide: Statistical Procedures, FREQ "Missing
   Values" (printed p.156): "The procedure displays the number of missing
   observations following each table" — the count line prints even when the
   table has no rows (every observation missing). The second step pins the
   WEIGHT interaction the chapter illustrates at Figure 3.12 (p.157): a single
   missing obs carrying weight 5 shows the WEIGHTED count
   (`Frequency Missing = 5`), not a row count of 1. */
data blanks;
  input resp @@;
  datalines;
. . .
;
run;
proc freq data=blanks; tables resp; run;

data wtd;
  input grade wt;
  datalines;
3 3
5 3
. 5
;
run;
proc freq data=wtd; tables grade; weight wt; run;
