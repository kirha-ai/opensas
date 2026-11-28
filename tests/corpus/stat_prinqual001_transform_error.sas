/* expect-rc: 1
   STAT-PRINQUAL-001: a PROC PRINQUAL step needs exactly one TRANSFORM
   statement with at least two variables. SAS 9.4 stops the step with
   "ERROR: A single TRANSFORM statement with at least one transformation name
   and at least two variables is required." and prints no table (verified for
   two TRANSFORM statements). Data: invented. */
options nocenter;
title;
data a;
input x y z;
datalines;
1 2 3
2 1 5
3 4 4
4 3 7
;
proc prinqual data=a out=o;
transform identity(x) identity(y z);
transform identity(x);
run;
