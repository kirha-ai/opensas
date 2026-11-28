/* STAT-CATMOD-003 DIRECT statement (PDF pp. 2196-2197): DIRECT variables
   enter the design matrix by their values (one column per effect), under
   maximum likelihood and RESPONSE MEANS (WLS); a DIRECT variable crossed
   with a class variable (value times deviation column, the effect named
   with the DIRECT variable first: a*x is x*a) and with another DIRECT
   variable (product of values); populations list class variables before
   DIRECT variables; design cells print as BEST5. (2.125 and -2.125 as
   2.125 and -2.13); unformatted DIRECT profile values are right-aligned,
   formatted ones left-aligned with the internal value in the design; a
   bare DIRECT in a later RUN group returns the variable to a class
   variable (SAS NOTEs: prior DIRECT and MODEL statements deleted).
   Expected listing: SAS 9.4 reference run of this program (2026-11-28).
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title;
data d1; input x y w @@; datalines;
1 1 10 1 2 5 2 1 8 2 2 7 3 1 4 3 2 11 4 1 3 4 2 12
;
data d2; input x a $ y w @@; datalines;
0.5 p 1 6 0.5 p 2 4 0.5 p 3 3 0.5 q 1 2 0.5 q 2 5 0.5 q 3 7
1.25 p 1 5 1.25 p 2 6 1.25 p 3 4 1.25 q 1 3 1.25 q 2 4 1.25 q 3 8
2.125 p 1 3 2.125 p 2 5 2.125 p 3 9 2.125 q 1 2 2.125 q 2 3 2.125 q 3 10
;
data d3; input x z y w @@; datalines;
1 0 1 9 1 0 2 3 1 1 1 7 1 1 2 5 2 0 1 6 2 0 2 6 2 1 1 4 2 1 2 8 3 0 1 3 3 0 2 9 3 1 1 2 3 1 2 11
;
proc format; value xf 1='one' 2='two' 3='three' 4='four'; run;
data d1f; set d1; format x xf.; run;
proc catmod data=d1; direct x; weight w; model y = x; run; direct; model y = x; run; quit;
proc catmod data=d1; direct x; weight w; model y = x / design; run; quit;
proc catmod data=d2; direct x; weight w; response means; model y = x a / design; run; quit;
proc catmod data=d2; direct x; weight w; model y = a x a*x / design; run; quit;
proc catmod data=d3; direct x z; weight w; model y = x z x*z / design; run; quit;
proc catmod data=d3; direct x; weight w; model y = x z x*z / design; run; quit;
proc catmod data=d1f; direct x; weight w; response means; model y = x / design; run; quit;
