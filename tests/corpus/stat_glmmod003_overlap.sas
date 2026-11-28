/* expect-rc: 0
 * STAT-GLMMOD-003: crossed-and-nesting effects in bar chains (only the term
 * itself survives), with a covariate (x*h(h g) -> x*h(g*h)), beside an effect
 * with the same columns (both kept), and nested within all of its own factors
 * (g(g)) (GLM pp.4095-4097 rules).
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of this program, 2026-11-28,
 * compared token by token (whitespace-normalised). Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input g $ h k x y1;
datalines;
a 1 1 1.5 4
a 2 2 2.5 5
b 1 1 3 6
b 2 2 4 7
c 1 2 5 8
a 1 1 6 4
b 2 2 7 5
a 2 1 8 6
;
title 'T1 bar with crossed-nesting term';
proc glmmod data=t; class g h k; model y1 = k*h(h) | g; run;
title 'T2 continuous in crossed-nesting';
proc glmmod data=t; class g h; model y1 = x*h(h g); run;
title 'T3 collision';
proc glmmod data=t; class g h; model y1 = h*g(g) h(g); run;
title 'T4 bar two crossed-nesting';
proc glmmod data=t; class g h k; model y1 = h*k(k) | g(g)@3; run;
title 'U1 at2';
proc glmmod data=t; class g h k; model y1 = h*k(k) | g@2; run;
title 'U2 two covariates';
proc glmmod data=t; class g h; model y1 = h*x*y1*h(h g) x*y1; run;
