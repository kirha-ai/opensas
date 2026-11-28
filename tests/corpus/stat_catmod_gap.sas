/* expect-rc: 2
   STAT-CATMOD-001 boundary: PROC CATMOD features owned by later CATMOD
   tickets or not yet verified must fail visibly (D-009 gap) and print no
   table: other RESPONSE functions, CONTRAST/DIRECT/FACTORS/LOGLIN/REPEATED/
   RESTRICT, ORDER=FREQ, formatted variables, effect names longer than
   24 characters, MODEL options other than DESIGN, nested effects, a
   direct design matrix, WHERE, MODEL / DESIGN with maximum likelihood,
   multiple responses and a Data Summary with fractional frequencies.
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t;
input g $ h $ y w @@;
datalines;
a x 1 3 a x 2 4 a y 1 2 a y 2 5 b x 1 6 b x 2 1 b y 1 2 b y 2 2
;
proc catmod data=t; weight w; response logits; model y=g; run;
proc catmod data=t; weight w; model y=g; contrast 'g' g 1; run;
proc catmod data=t; weight w; direct h; model y=g; run;
proc catmod data=t; weight w; loglin g; model y=g; run;
proc catmod data=t order=freq; weight w; model y=g; run;
data fm; set t; format y 3.; run;
proc catmod data=fm; weight w; model y=g; run;
data ln; set t; rename g=a_very_long_variable_name_x h=b_long; run;
proc catmod data=ln namelen=30; weight w; model y=a_very_long_variable_name_x*b_long; run;
proc catmod data=t; weight w; model y=g / pred; run;
proc catmod data=t; weight w; model y=g h(g); run;
proc catmod data=t; weight w; model y=(1 0, 1 1, 1 0, 1 1); run;
proc catmod data=t; weight w; where w > 1; model y=g; run;
proc catmod data=t; weight w; model y=g / design; run;
proc catmod data=t; weight w; model y*g=h; run;
data f; set t; if _n_ = 1 then w = w + 0.5; run;
proc catmod data=f; weight w; response means; model y=g; run;
