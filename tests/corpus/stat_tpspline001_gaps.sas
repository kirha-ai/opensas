/* expect-rc: 2
 * STAT-TPSPLINE-001: valid PROC TPSPLINE requests outside the verified scope
 * fail visibly with no listing (the MODEL options and forms once listed
 * here are implemented by STAT-TPSPLINE-003): SCORE (STAT-TPSPLINE-005), the
 * COEF output keyword (STAT-TPSPLINE-006), ODS Graphics plots with ODS Graphics
 * on, by default or by request, and an unverified plot suboption
 * (STAT-TPSPLINE-008), and OUTPUT rows for observations excluded by a
 * missing response or a FREQ value below one (STAT-TPSPLINE-006).
 * Invented data.
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
proc tpspline data=pts; model y = (x1 x2); score data=pts out=sc; run;
proc tpspline data=pts; model y = (x1 x2); output out=o coef; run;
ods graphics on;
proc tpspline data=pts plots=fit; model y = (x1 x2); run;
proc tpspline data=pts; model y = (x1 x2); run;
ods graphics off;
proc tpspline data=pts plots=fit(bogus); model y = (x1 x2); run;
proc tpspline data=miss; model y = (x1 x2); output out=o2; run;
proc tpspline data=pts; freq f; model y = (x1 x2); output out=o3; run;
