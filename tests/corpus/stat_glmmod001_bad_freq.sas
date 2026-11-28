/* expect-rc: 1
 * STAT-GLMMOD-001: a character FREQ variable is a user error (FREQ names a
 * numeric variable, S154 p.4239): visible ERROR, rc 1, no listing. Invented data.
 */
data a;
input g $ y;
datalines;
A 1
B 2
A 3
;
proc glmmod data=a;
class g;
freq g;
model y = g;
run;
