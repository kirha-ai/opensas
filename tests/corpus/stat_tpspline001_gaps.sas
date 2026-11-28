/* expect-rc: 2
 * STAT-TPSPLINE-001: valid PROC TPSPLINE requests outside the verified scope
 * fail visibly with no listing: regression variables, one smoothing
 * variable, two dependent variables, LAMBDA0=, DF=, M=3, DISTANCE=1, a
 * LAMBDA= list (STAT-TPSPLINE-003), SCORE (STAT-TPSPLINE-005), the RESID
 * output keyword (STAT-TPSPLINE-006), PLOTS= requests (STAT-TPSPLINE-008),
 * a FREQ value below one, OUTPUT with a missing response, and an empty
 * input data set. Invented data.
 */
options nosyntaxcheck;
data pts;
input x1 x2 z y y2 f @@;
datalines;
0 0 1 1 2 1  1 0 2 2 3 1  0 1 3 3 1 1  1 1 4 5 2 0.5  2 2 5 4 4 1  2 0 1 3 3 1
;
data miss;
set pts;
if _n_ = 2 then y = .;
run;
data none;
set pts;
stop;
run;
proc tpspline data=pts; model y = z (x1 x2); run;
proc tpspline data=pts; model y = (x1); run;
proc tpspline data=pts; model y y2 = (x1 x2); run;
proc tpspline data=pts; model y = (x1 x2) / lambda0=0.1; run;
proc tpspline data=pts; model y = (x1 x2) / df=3; run;
proc tpspline data=pts; model y = (x1 x2) / m=3; run;
proc tpspline data=pts; model y = (x1 x2) / distance=1; run;
proc tpspline data=pts; model y = (x1 x2) / lambda=(0.1 0.2); run;
proc tpspline data=pts; model y = (x1 x2); score data=pts out=sc; run;
proc tpspline data=pts; model y = (x1 x2); output out=o coef; run;
proc tpspline data=pts plots=fit; model y = (x1 x2); run;
proc tpspline data=pts; freq f; model y = (x1 x2); run;
proc tpspline data=miss; model y = (x1 x2); output out=o2; run;
proc tpspline data=none; model y = (x1 x2); run;
