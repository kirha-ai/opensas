/* expect-rc: 2
 * STAT-HPREG-001: PROC HPREG features owned by later HPREG and shared
 * high-performance tickets (SELECTION, OUTPUT, PARTITION, PERFORMANCE, CODE,
 * MODEL options such as CLB and VIF, CLASS options, NAMELEN=, NOCLPRINT),
 * crossed effects, the intercept-only model and mean squares below 0.01
 * (a display format not yet verified) must each fail visibly (D-009 gap)
 * without printing a partial analysis. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data small;
input b g $ x1 x2 y;
datalines;
1 A 1 5 2.1
1 B 2 3 2.9
1 A 3 8 4.2
1 B 4 1 4.8
1 A 5 7 6.1
1 B 6 2 6.7
1 A 7 9 8.3
2 B 8 4 8.8
2 A 1 2 1.0
2 B 2 6 2.0
2 A 3 1 3.0
2 B 4 5 4.0
2 A 5 3 5.0
2 B 6 8 6.0
;
run;
proc hpreg data=small;
class g;
model y = x1 g x2;
selection method=stepwise;
run;
proc hpreg data=small;
model y = x1 x2 / vif clb;
run;
proc hpreg data=small;
model y = x1 x2;
output out=pred p=p;
run;
proc hpreg data=small;
model y = x1 x2;
partition fraction(validate=0.3);
run;
proc hpreg data=small;
model y = x1 x2;
performance nthreads=2;
run;
proc hpreg data=small namelen=30;
model y = x1 x2;
run;
proc hpreg data=small noclprint;
class g;
model y = x1 g;
run;
proc hpreg data=small;
class g / upcase;
model y = x1 g;
run;
proc hpreg data=small;
model y = x1*x2;
run;
proc hpreg data=small;
model y = ;
run;
proc hpreg data=small;
by b;
model y = x1 x2;
run;
