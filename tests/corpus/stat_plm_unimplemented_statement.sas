/* STAT-PLM-001: expect-rc: 2
 * A documented PROC PLM analysis statement that is not implemented yet must
 * fail loudly (D-009 gap) and must not print the default tables as if the
 * step had succeeded. Invented data. */
data lines;
input g $ x y @@;
datalines;
A 1 4 A 2 6 A 3 7 B 1 9 B 2 13 B 3 12
;
proc glm data=lines noprint;
class g;
model y = g x;
store fit;
run;
proc plm restore=fit;
lsmeans g / diff;
run;
