/* expect-rc: 2
   STAT-CATMOD-005 boundary: design-matrix forms not implemented or not
   verified fail visibly (D-009 gap) and print no table: a crossed effect
   within a nested effect (A*B(C)) and an effect nested within several
   variables (A(B C)), both Specification of Effects (STAT-CATMOD-004); an
   unquoted name as a nested-by-value value; an effect nested within itself;
   an absent nested level combination (SAS marks redundant parameters, '*');
   DIRECT effects and LOGLIN design matrices (STAT-CATMOD-003); _RESPONSE_
   and the AVERAGED, NOINT and PARAM=REF design forms (STAT-CATMOD-004);
   REPEATED (later CATMOD ticket).
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data t;
input b a c y w @@;
datalines;
1 1 1 0 5 1 1 2 1 7 1 2 1 2 9 1 2 2 0 8 2 1 1 1 4 2 1 2 2 6
2 2 1 0 3 2 2 2 1 9 1 1 1 2 5 2 2 2 0 6 1 2 2 1 6 2 1 1 2 2
;
proc catmod data=t; weight w; response means; model y=a*c(b); run;
proc catmod data=t; weight w; response means; model y=a(b c); run;
proc catmod data=t; weight w; response means; model y=a(b=one); run;
proc catmod data=t; weight w; response means; model y=a(a); run;
data t2; set t; if b = 2 and a = 2 then delete; run;
proc catmod data=t2; weight w; response means; model y=a b(a); run;
proc catmod data=t; weight w; direct c; response means; model y=c; run;
proc catmod data=t; weight w; model a*y=_response_; loglin a y; run;
proc catmod data=t; weight w; model y=_response_; run;
proc catmod data=t; weight w; model y=a / averaged; run;
proc catmod data=t; weight w; response means; model y=a / noint; run;
proc catmod data=t; weight w; response means; model y=a / param=ref; run;
proc catmod data=t; weight w; model y=a; repeated time 2; run;
