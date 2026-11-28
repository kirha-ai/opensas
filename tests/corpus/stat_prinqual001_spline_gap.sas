/* expect-rc: 2
   STAT-PRINQUAL-001 boundary: optimal transformations (here SPLINE,
   STAT-PRINQUAL-003) are valid SAS that opensas does not compute yet. The
   step must fail visibly (D-009 gap), print no iteration history and create
   no OUT= data set, never an IDENTITY analysis in disguise. Data: invented. */
options nocenter;
title;
data a;
input x y z;
datalines;
1 2 3
2 1 5
3 4 4
4 3 7
5 6 6
;
proc prinqual data=a out=o;
transform spline(x y) identity(z);
run;
