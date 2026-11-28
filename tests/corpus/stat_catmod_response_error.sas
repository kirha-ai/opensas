/* expect-rc: 1
   STAT-CATMOD-004 user error: a RESPONSE row whose number of coefficients
   differs from the number of response levels (p. 2212: one coefficient
   per response level). Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t; input g $ y $ w @@; datalines;
a r1 10 a r2 20 a r3 15 b r1 12 b r2 9 b r3 30
;
proc catmod data=t; weight w; response 1 0; model y = g; run; quit;
