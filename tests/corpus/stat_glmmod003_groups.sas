/* expect-rc: 0
 * STAT-GLMMOD-003: a pattern group of two dependents (a repeated y1) beside
 * other patterns, BY groups whose passes differ (_YPASS_ after the BY
 * variable), passes with different CLASS levels (union Class Level
 * Information), and a crossed factor that is also nesting, k*h(h g), named
 * h*k(g*h) (S154 pp.4239-4240, GLM pp.4095-4096).
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of these steps (same data and
 * statements), 2026-11-28, compared token by token (whitespace-normalised).
 * Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input b g $ h k y1 y2 y3;
datalines;
1 a 1 1 4 5 6
1 a 2 2 5 . 7
1 b 1 1 6 7 8
1 b 2 2 7 8 9
1 c 1 2 8 9 .
2 a 1 1 4 5 6
2 b 2 2 5 6 7
2 a 2 1 6 7 8
;
title 'S1 group of two plus one';
proc glmmod data=t outparm=p; class h; model y1 y2 y3 y1 = h; run;
proc print data=p; run;
title 'S2 by with passes';
proc glmmod data=t outdesign=d2 outparm=p2; by b; class h; model y1 y2 = h; run;
proc print data=d2; run; proc print data=p2; run;
title 'S3 passes different levels';
proc glmmod data=t; class g; model y1 y3 = g; run;
title 'S4 crossed nested';
proc glmmod data=t; class g h k; model y1 = k*h(h g) h*k(k); run;
