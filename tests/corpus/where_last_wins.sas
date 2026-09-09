data src;
  input x;
  datalines;
1
3
5
6
8
;
run;

/* BUG-whereplacelast: a second plain WHERE REPLACES the first (SAS 9.4:
   a later plain WHERE supersedes the earlier one; only WHERE ALSO ANDs).
   Here the filter must be x > 5 (the LAST), not x > 1. */
data _null_;
  set src;
  where x > 1;
  where x > 5;
  put "x=" x;
run;
