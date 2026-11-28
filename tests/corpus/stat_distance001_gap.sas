/* expect-rc: 2
 * STAT-DISTANCE-001: valid PROC DISTANCE requests outside the implemented
 * coordinate-distance path (here METHOD=GOWER, owned by STAT-DISTANCE-003)
 * must fail visibly (D-009 gap) and create no data set. Invented data.
 */
options nodate nonumber nocenter;
title; footnote;
data s;
input x z;
datalines;
1 2
3 5
4 4
;
run;
proc distance data=s method=gower out=g;
var interval(x z);
run;
proc print data=g; run;
