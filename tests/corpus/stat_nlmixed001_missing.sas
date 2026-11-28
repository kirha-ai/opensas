/* expect-rc: 1
 * STAT-NLMIXED-001: a missing SUBJECT= value stops PROC NLMIXED with
 *   ERROR: SUBJECT= variable must be nonmissing in observation 9.
 * as SAS 9.4 does for these invented rows (observation 9 of the input data
 * set). Without that row SAS reports 9 used / 2 not used observations (the
 * missing x and the missing y), 4 subjects, at most 3 per subject; those
 * Dimensions values are checked in src/stat/nlmixed_tests.zig because the
 * estimation that follows them is a gap (STAT-NLMIXED-002). Nothing is
 * printed.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data d;
input s c x y;
datalines;
2 1 1 3.2
1 1 2 4.1
2 2 3 5.0
3 1 4 6.3
1 2 5 6.9
3 2 6 8.2
2 1 7 9.0
1 1 . 5.5
. 2 2 4.4
3 1 3 .
4 2 5 7.7
4 1 6 7.1
;
run;
proc nlmixed data=d;
eta = b0 + b1*x + u;
model y ~ normal(eta, s2);
random u ~ normal(0, g) subject=s;
run;
