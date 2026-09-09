/* First non-missing across candidate columns (COALESCE) */
data d; input x1 x2 x3; datalines;
. 5 9
. . 3
7 . .
. . .
;
run;
data c;
  set d;
  firstval = coalesce(x1, x2, x3);
run;
proc print data=c; var x1 x2 x3 firstval; run;
