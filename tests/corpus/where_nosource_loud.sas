/* BUG-wherestmtnosource: a WHERE statement in a DATA step needs an input
   SAS data set. With raw datalines INPUT, SAS 9.4 errors:
   "No input data sets available for WHERE statement." The old executor
   silently ignored the WHERE and emitted all four rows.
   expect-rc: 1 */
data _null_;
  put "BEFORE: runs";
run;

data d;
  input x;
  where x > 10;
  datalines;
5
12
3
20
;
run;

proc print data=d; run;

data _null_;
  put "AFTER: must not print";
run;
