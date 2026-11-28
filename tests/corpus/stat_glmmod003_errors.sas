/* expect-rc: 1
 * STAT-GLMMOD-003: invalid MODEL statements, each a visible ERROR with no
 * listing (messages as SAS 9.4 words them, live run 2026-11-28): a character
 * non-CLASS effect, a continuous nesting variable, a MODEL without "=", an
 * unknown MODEL option, a character dependent. Invented data.
 */
options nosyntaxcheck;
data t;
input g $ h x y1;
datalines;
a 1 1.5 4
a 2 2.5 5
b 1 3 6
b 2 4 7
;
proc glmmod data=t; model y1 = g; run;
proc glmmod data=t; class h; model y1 = h(x); run;
proc glmmod data=t; model y1; run;
proc glmmod data=t; class h; model y1 = h / solution; run;
proc glmmod data=t; class h; model g = h; run;
