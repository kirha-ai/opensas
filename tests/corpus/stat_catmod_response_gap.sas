/* expect-rc: 2
   STAT-CATMOD-004 boundary (D-009 gaps, no table): RESPONSE with several
   rows of coefficients (several functions per population), RESPONSE
   keyword functions (LOGITS, MARGINALS, READ), MODEL / FREQ PROB CLPARM
   under maximum likelihood, the @ operator, bar notation with nested
   effects, an effect name over 24 characters with NAMELEN=, MODEL options
   still unimplemented (NOINT, PARAM=, ML), _RESPONSE_ and a direct design
   matrix. Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t; input g $ h $ y $ w @@; datalines;
a p r1 10 a p r2 20 a p r3 15 a q r1 12 a q r2 9 a q r3 30
b p r1 25 b p r2 14 b p r3 11 b q r1 8 b q r2 17 b q r3 22
;
data t2; input LongVarNameAlpha $ LongerVariableNameBeta $ y $ w @@; datalines;
a u r1 10 a u r2 20 a v r1 15 a v r2 9 b u r1 25 b u r2 14 b v r1 11 b v r2 13
;
proc catmod data=t; weight w; response 1 0 0, 0 1 0; model y = g; run; quit;
proc catmod data=t; weight w; response logits; model y = g; run; quit;
proc catmod data=t; weight w; response marginals; model y = g; run; quit;
proc catmod data=t; weight w; model y = g / freq; run; quit;
proc catmod data=t; weight w; model y = g / prob; run; quit;
proc catmod data=t; weight w; model y = g / clparm; run; quit;
proc catmod data=t; weight w; response 1 2 3; model y = g|h@1; run; quit;
proc catmod data=t; weight w; response 1 2 3; model y = g|h(g); run; quit;
proc catmod data=t2 namelen=30; weight w; response 1 0; model y = LongVarNameAlpha|LongerVariableNameBeta; run; quit;
proc catmod data=t; weight w; response 1 2 3; model y = g / noint; run; quit;
proc catmod data=t; weight w; response 1 2 3; model y = g / param=ref; run; quit;
proc catmod data=t; weight w; model y = _response_; run; quit;
proc catmod data=t; weight w; response 1 2 3; model y = (1 0, 1 1, 1 0, 1 1); run; quit;
