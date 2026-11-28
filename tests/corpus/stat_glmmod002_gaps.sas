/* expect-rc: 2
 * STAT-GLMMOD-002: Design Points columns whose SAS format was not probed
 * must fail visibly (D-009 gap) and print no partial listing: a negative
 * value in a column written E8.2 (wider than 8 with decimals) and an
 * integer column wider than nine digits. Invented data.
 */
options nosyntaxcheck;
data e;
input y z;
datalines;
-1234567.5 1
0.25 2
;
proc glmmod data=e;
model y = z;
run;
data f;
input y z;
datalines;
1 1234567890
2 1
;
proc glmmod data=f;
model y = z;
run;
