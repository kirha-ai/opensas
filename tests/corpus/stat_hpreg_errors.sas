/* expect-rc: 1
 * STAT-HPREG-001: invalid PROC HPREG declarations are user errors (rc 1):
 * an unknown option, ALPHA= outside (0,1), a missing MODEL statement, a
 * second MODEL statement, CLASS after MODEL, a character response or
 * regressor not named in CLASS, a character FREQ variable, an unknown ID
 * variable. Nothing is printed. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data small;
input g $ x1 x2 y f;
datalines;
A 1 5 2.1 1
B 2 3 2.9 1
A 3 8 4.2 2
B 4 1 4.8 1
A 5 7 6.1 1
B 6 2 6.7 1
;
run;
proc hpreg data=small bogus;
model y = x1;
run;
proc hpreg data=small alpha=1.5;
model y = x1;
run;
proc hpreg data=small;
class g;
run;
proc hpreg data=small;
model y = x1;
model y = x2;
run;
proc hpreg data=small;
model y = x1;
class g;
run;
proc hpreg data=small;
model g = x1;
run;
proc hpreg data=small;
model y = x1 g;
run;
proc hpreg data=small;
freq g;
model y = x1;
run;
proc hpreg data=small;
id nosuch;
model y = x1;
run;
