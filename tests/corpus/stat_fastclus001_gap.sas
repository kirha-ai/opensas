/* expect-rc: 2
 * STAT-FASTCLUS-001: valid PROC FASTCLUS requests outside the implemented
 * least-squares path must fail visibly (D-009 gap) and create no data set:
 * here LEAST=1 (Lp clustering, owned by STAT-FASTCLUS-003). Invented data.
 */
options nodate nonumber nocenter;
title; footnote;
data s;
input x y;
datalines;
1 1
2 3
8 8
9 9
;
run;
proc fastclus data=s maxc=2 maxiter=5 least=1 out=o;
var x y;
run;
proc print data=o; run;
