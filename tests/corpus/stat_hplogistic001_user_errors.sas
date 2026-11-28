/* expect-rc: 1
 * STAT-HPLOGISTIC-001: invalid PROC HPLOGISTIC requests are user errors
 * with no listing. Invented data.
 */
options nosyntaxcheck;
data d;
input y x c $ f;
datalines;
0 1 a 1
1 2 b 1
0 3 a 2
1 4 b 1
;
proc hplogistic data=d; class c; run;
proc hplogistic data=d; model y = zz; run;
proc hplogistic data=d; model y = c; run;
proc hplogistic data=d; model y = x; freq c; run;
proc hplogistic data=d; model y = x; weight; run;
proc hplogistic data=d; model y = x; class c; run;
proc hplogistic data=d data=d; model y = x; run;
proc hplogistic data=d alpha=2; model y = x; run;
proc hplogistic data=d bogus; model y = x; run;
proc hplogistic data=d; class c c; model y = c; run;
proc hplogistic data=d; model y = y x; run;
proc hplogistic data=nosuch; model y = x; run;
