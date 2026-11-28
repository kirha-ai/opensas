/* expect-rc: 1
   STAT-CATMOD-001: invalid PROC CATMOD input is a user error and prints no
   table: an unknown variable, the response used as an explanatory variable,
   RESPONSE MEANS on a character response, a character WEIGHT variable, an
   invalid PROC option, an effect specified twice, an unknown statement and
   negative weights (message as in SAS), NAMELEN= outside 24-200, and an
   empty, fully excluded (all weights missing) or WHERE-emptied input
   ("The data set contains 0 nonmissing observations with positive
   weight.", as in SAS; no listing).
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t;
input g $ h $ y w c $ @@;
datalines;
a x 1 3 u a x 2 4 v a y 1 2 u a y 2 5 v b x 1 6 u b x 2 1 v b y 1 2 u b y 2 2 v
;
proc catmod data=t; weight w; model y=nosuch; run;
proc catmod data=t; weight w; model y=g y; run;
proc catmod data=t; weight w; response means; model c=g; run;
proc catmod data=t; weight c; model y=g; run;
proc catmod data=t bogus; weight w; model y=g; run;
proc catmod data=t; weight w; model y=g g; run;
proc catmod data=t; weight w; frobnicate; model y=g; run;
data n; set t; if _n_ = 2 then w = -1; run;
proc catmod data=n; weight w; response means; model y=g; run;
proc catmod data=t namelen=10; weight w; model y=g; run;
data z; set t; stop; run;
proc catmod data=z; weight w; model y=g; run;
data x; set t; w = .; run;
proc catmod data=x; weight w; model y=g; run;
proc catmod data=t; weight w; where w > 100; model y=g; run;
