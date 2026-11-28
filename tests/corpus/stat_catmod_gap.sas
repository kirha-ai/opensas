/* expect-rc: 2
   STAT-CATMOD-001 boundary: PROC CATMOD features owned by later CATMOD
   tickets or not yet verified must fail visibly (D-009 gap) and print no
   table: other RESPONSE functions, CONTRAST/DIRECT/FACTORS/LOGLIN/REPEATED/
   RESTRICT, effect names longer than 24 characters, MODEL options other
   than DESIGN, bar effects, a direct design matrix, multiple responses, fractional weights with
   whole-number sums, a fractional Data Summary value of 8 characters,
   RESPONSE MEANS on a format that merges response values, DATA= options
   other than WHERE=, maximum likelihood with a near-zero cell (SAS marks
   such parameters infinite) and an estimate below 0.001 in magnitude.
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
data ln; set t; rename g=a_very_long_variable_name_x h=b_long; run;
proc catmod data=ln namelen=30; weight w; model y=a_very_long_variable_name_x*b_long; run;
proc catmod data=t; weight w; model y=g / pred; run;
proc catmod data=t; weight w; model y=g|h; run;
proc catmod data=t; weight w; model y=(1 0, 1 1, 1 0, 1 1); run;
proc catmod data=t; weight w; model y*g=h; run;
data f; set t; if _n_ <= 2 then w = w + 0.5; run;
proc catmod data=f; weight w; response means; model y=g; run;
data f8; set t; w = w * 1000; if _n_ = 1 then w = w + 0.25; run;
proc catmod data=f8; weight w; response means; model y=g; run;
proc format; value mm 1, 2 = 'one'; run;
data fm; set t; format y mm.; if g = 'a' then y = 3; run;
proc catmod data=fm; weight w; response means; model y=g; run;
proc catmod data=t(keep=g y w); weight w; model y=g; run;
data z; set t; if g = 'b' and y = 2 then w = 0.000001; run;
proc catmod data=z; weight w; model y=g; run;
data r; input g $ y @@; datalines;
b 2 b 2 a 1 a 1 a 2 c 3 c 3 c 1 b 1 a 3 c 2 b 3
;
proc catmod data=r order=freq; response means; model y=g; run;
/* A chi-square of 1E6 or more (STAT-CATMOD-005 reference run: SAS shows
   1318307.78 as 1318308). */
data u; input g y w @@; datalines;
1 1 30000 1 2 40000 2 1 25000 2 2 35000
;
proc catmod data=u; weight w; response means; model y=g; run;
/* Input Data Sets: response functions and covariances read directly
   (TYPE=EST, RESPONSE READ, _F_; guide example p.2210). */
data direct(type=est);
input b1-b4 _type_ $ _name_ $8.;
datalines;
0.590463   0.384720    0.273269  0.136458                   PARMS        .
0.001690   0.000911    0.000474  0.000432                   COV          B1
0.000911   0.001823    0.000031  0.000102                   COV          B2
0.000474   0.000031    0.001056  0.000477                   COV          B3
0.000432   0.000102    0.000477  0.000396                   COV          B4
;
proc catmod data=direct;
response read b1-b4;
model _f_=_response_;
factors age 2, race 2 / _response_=age race;
run;
