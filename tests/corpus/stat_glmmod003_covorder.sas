/* expect-rc: 0
 * STAT-GLMMOD-003: covariates of a crossed-and-nesting effect follow their
 * model-wide first appearance, not the written order (x z*x*h(h g) ->
 * x*z*h(g*h); z*x*h(h g) x*z -> z*x*h(g*h), z*x; z x*z*h(h) -> z*x*h(h)).
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) run of this program, 2026-11-28,
 * compared token by token (whitespace-normalised). Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input g $ h z x y1;
datalines;
a 1 2 1.5 4
a 2 3 2.5 5
b 1 1 3 6
b 2 4 4 7
c 1 2 5 8
a 1 5 6 4
b 2 1 7 5
a 2 3 8 6
;
title 'V1 model order x z, written z x';
proc glmmod data=t; class g h; model y1 = x z*x*h(h g); run;
title 'V2 written z x, then x*z';
proc glmmod data=t; class g h; model y1 = z*x*h(h g) x*z; run;
title 'V3 written x z after z';
proc glmmod data=t; class g h; model y1 = z x*z*h(h); run;
