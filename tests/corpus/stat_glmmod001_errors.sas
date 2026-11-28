/* expect-rc: 1
 * STAT-GLMMOD-001: documented invalid inputs, each a visible ERROR with no
 * listing (messages as SAS 9.4 words them): NAMELEN= outside 20..200, a
 * second FREQ statement, an empty input data set, a missing MODEL
 * statement, and an unsorted BY variable. Invented data.
 */
options nosyntaxcheck;
data a;
input g $ y f;
datalines;
B 1 1
A 2 1
;
data e; set a; if y > 100; run;
proc glmmod data=a namelen=10; class g; model y=g; run;
proc glmmod data=a; class g; freq f; freq y; model y=g; run;
proc glmmod data=e; class g; model y=g; run;
proc glmmod data=a; class g; run;
proc glmmod data=a; by g; model y=f; run;
