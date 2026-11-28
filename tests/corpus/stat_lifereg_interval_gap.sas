/* expect-rc: 2
 * STAT-LIFEREG-001: the MODEL (lower, upper) interval-censored response is
 * valid PROC LIFEREG syntax that the shared survival-data contract does not
 * execute yet; it must fail visibly (D-009 gap). Invented data.
 */
data visits;
input lo hi dose;
datalines;
. 4 1
3 5 1
6 6 2
7 . 2
;
run;
proc lifereg data=visits;
model (lo, hi) = dose;
run;
