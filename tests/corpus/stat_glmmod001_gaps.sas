/* expect-rc: 2
 * STAT-GLMMOD-001: CLASS / TRUNCATE is valid SAS (S154 p.4238) that opensas
 * does not implement; the step must fail visibly (D-009 gap) and print no
 * partial listing. Invented data.
 */
data a;
input g $ y;
datalines;
A 1
B 2
A 3
;
proc glmmod data=a;
class g / truncate;
model y = g;
run;
