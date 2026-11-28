/* expect-rc: 2
 * STAT-GLMMOD-003: valid SAS that opensas does not implement must fail
 * visibly (D-009 gap) and print no partial listing: an effect whose crossed
 * factor also appears in its own nesting list (SAS 9.4 accepts g*h(g)), and
 * several dependents sharing one missing-value pattern beside a dependent
 * with another pattern (pass order/headings not SAS-verified). (CLASS /
 * TRUNCATE, formerly gapped here, is implemented: stat_glmmod003_model.sas.)
 * Invented data.
 */
options nosyntaxcheck;
data a;
input g $ h y1 y2 y3;
datalines;
A 1 1 2 3
B 2 2 . 4
A 2 3 4 5
B 1 4 5 6
;
proc glmmod data=a;
class g h;
model y1 = g*h(g);
run;
proc glmmod data=a;
class g;
model y1 y2 y3 = g;
run;
