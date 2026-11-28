/* expect-rc: 0
 * STAT-GLMMOD-003: dependents in one pass per missing-value pattern,
 * in MODEL order, with _YPASS_ in OUTDESIGN=/OUTPARM=; unused CLASS variables;
 * a repeated dependent; NOINT without effects; MODEL SINGULAR= (S154 pp.4239-4240).
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of these steps (same data and statements),
 * 2026-11-28, compared token by token (whitespace-normalised). Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input g $ h x y1 y2 y3 y4;
datalines;
a 1 1.5 4 5 6 .
a 2 2.5 5 . 7 1
b 1 3 6 7 . 2
b 2 4 7 8 9 3
a 2 5 8 9 10 .
b 1 6 9 . 11 4
;
title 'R1 mixed groups';
proc glmmod data=t outdesign=d outparm=p; class h; model y2 y1 y4 y3 = h; run;
proc print data=d; run; proc print data=p; run;
title 'R2 unused class';
proc glmmod data=t; class g h; model y1 = h; run;
title 'R3 common missing';
proc glmmod data=t; class h; model y2 y2 = h; run;
title 'R4 zerobased noint none';
proc glmmod data=t outdesign=d4 outparm=p4; model y1 = / noint; run;
title 'R5 noint class';
proc glmmod data=t; class g; model y1 = g / noint singular=1e-7; run;
