/* expect-rc: 1
 * STAT-TPSPLINE-001: documented invalid input is a user error with no
 * listing: no MODEL statement, no parenthesized smoothing variables (at
 * least one is required, p.10303), regression variables after the
 * smoothing list, a variable in both roles, a character response, an
 * unknown variable, ALPHA= outside (0,1), a non-positive LAMBDA= value,
 * M= not a positive integer, a value list without parentheses, OUTPUT without OUT=, an unknown PROC option,
 * a missing input data set and BY data that are not sorted. Invented data.
 */
options nosyntaxcheck;
data pts;
input x1 x2 y g name $ @@;
datalines;
0 0 1 2 a  1 0 2 1 b  0 1 3 2 c  1 1 5 1 d  2 2 4 2 e  2 0 3 1 f
;
proc tpspline data=pts; run;
proc tpspline data=pts; model y = x1 x2; run;
proc tpspline data=pts; model y = (x1 x2) g; run;
proc tpspline data=pts; model y = (x1 y); run;
proc tpspline data=pts; model name = (x1 x2); run;
proc tpspline data=pts; model y = (x1 zz); run;
proc tpspline data=pts; model y = (x1 x2) / alpha=2; run;
proc tpspline data=pts; model y = (x1 x2) / lambda=(0 1); run;
proc tpspline data=pts; model y = (x1 x2) / m=1.5; run;
proc tpspline data=pts; model y = (x1 x2) / lognl=-2; run;
proc tpspline data=pts; model y = (x1 x2); output pred; run;
proc tpspline data=pts bogus; model y = (x1 x2); run;
proc tpspline data=nosuch; model y = (x1 x2); run;
proc tpspline data=pts; by g; model y = (x1 x2); run;
