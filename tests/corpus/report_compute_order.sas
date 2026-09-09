/* BUG-reportcomputeorder: SAS 9.4 evaluates PROC REPORT COMPUTE blocks in
   COLUMN order (left-to-right in the COLUMN statement), NOT source-text order.
   Here the block for `d` is written BEFORE the block for `c` it depends on;
   because column c precedes d, c must still be computed first so d = (a+b)*2,
   never missing. Pins the column-order eval fix. */
data t;
  input a b;
  datalines;
1 2
3 4
;
run;

proc report data=t nowd;
  column a b c d;
  define c / computed;
  define d / computed;
  compute d;
    d = c * 2;
  endcomp;
  compute c;
    c = a + b;
  endcomp;
run;
