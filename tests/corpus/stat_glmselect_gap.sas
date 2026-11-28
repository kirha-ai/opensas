/* expect-rc: 2
 * STAT-GLMSELECT-001: PLOTS=, FREQ and WEIGHT analyses, SELECTION= methods
 * other than the default, the PARTITION statement, crossed effects and the
 * listing without DETAILS=ALL STATS=ALL are not implemented; each step must
 * fail visibly (D-009 gap) without printing a partial analysis. Invented data.
 */
options linesize=160;
data small;
input g $ x1 x2 f w y;
datalines;
A 1 5 1 1.0 2.1
B 2 3 2 0.5 2.9
A 3 8 1 1.5 4.2
B 4 1 1 1.0 4.8
A 5 7 2 2.0 6.1
B 6 2 1 1.0 6.7
A 7 9 1 0.5 8.3
B 8 4 1 1.0 8.8
;
run;
proc glmselect data=small plots=all;
model y = x1 x2 / details=all stats=all;
run;
proc glmselect data=small;
freq f;
model y = x1 x2 / details=all stats=all;
run;
proc glmselect data=small;
weight w;
model y = x1 x2 / details=all stats=all;
run;
proc glmselect data=small;
model y = x1 x2 / selection=lasso;
run;
proc glmselect data=small;
partition fraction(validate=0.3);
model y = x1 x2;
run;
proc glmselect data=small;
class g;
model y = x1 x2 g x1*g / details=all stats=all;
run;
proc glmselect data=small;
model y = x1 x2;
run;
