/* FEAT-procreport-2 increment-1: a COMPUTED column defined by a simple
   arithmetic expression over other displayed numeric columns in the same row. */
data d;
  input a b;
  datalines;
1 10
2 20
3 30
;
run;

proc report data=d nowd;
  column a b tot;
  define a / display;
  define b / display;
  define tot / computed;
  compute tot;
    tot = a + b;
  endcomp;
run;
