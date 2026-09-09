/* NOTE-lineoobcol: a PROC REPORT LINE with an out-of-range @col column pointer
   (@9999) must clamp to the default line-size (132), not pad thousands of spaces.
   The in-range `@5 'Total'` control is unchanged (SAS pads to column 5). */
data sales;
  input reg $ units;
  datalines;
E 1
E 2
W 4
;
run;

proc report data=sales nowd;
  column reg units;
  define reg / group;
  define units / analysis sum;
  rbreak after / summarize;
  compute after;
    line @5 'Total';
    line @9999 'clamped';
  endcomp;
run;
