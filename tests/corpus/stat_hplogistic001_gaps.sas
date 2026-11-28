/* expect-rc: 2
 * STAT-HPLOGISTIC-001: valid PROC HPLOGISTIC requests outside the verified
 * scope fail visibly with no listing: optimization and output options,
 * SELECTION (STAT-HP-004), OUTPUT, PERFORMANCE, model options, interactions,
 * events/trials, a three-level response, a character response, a FREQ
 * value below one, an unused CLASS variable and an empty data set.
 * Invented data.
 */
options nosyntaxcheck;
data d;
input y x c $ r $ t f;
datalines;
0 1 a u 2 1
1 2 b v 3 0
0 3 a u 2 2
1 4 b v 3 1
2 5 a u 4 1
;
data two;
set d;
if y < 2;
run;
data none;
set d;
stop;
run;
proc hplogistic data=two gconv=1e-10; model y = x; run;
proc hplogistic data=two technique=newrap; model y = x; run;
proc hplogistic data=two itdetails; model y = x; run;
proc hplogistic data=two; model y = x; selection method=forward; run;
proc hplogistic data=two; model y = x; output out=o; run;
proc hplogistic data=two; model y = x; performance nthreads=1; run;
proc hplogistic data=two; model y = x / link=probit; run;
proc hplogistic data=two; class c; model y = c*x; run;
proc hplogistic data=two; model y/t = x; run;
proc hplogistic data=d; model y = x; run;
proc hplogistic data=two; model r = x; run;
proc hplogistic data=two; model y = x; freq f; run;
proc hplogistic data=two; class c; model y = x; run;
proc hplogistic data=none; model y = x; run;
