/* expect-rc: 1
   STAT-CATMOD-003 DIRECT user errors (SAS reference run, 2026-11-28; SAS
   prints no listing for any of them): a character DIRECT variable is
   "Variable a in list does not match type prescribed for this list.", an
   unknown one "Variable NOSUCH not found.", and a DIRECT after the MODEL
   of the same RUN group "The DIRECT statement must precede the MODEL
   statement." (p. 2196).
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data d1; input x a $ y w @@; datalines;
1 p 1 10 1 q 2 5 2 p 1 8 2 q 2 7 3 p 1 4 3 q 2 11 4 p 1 3 4 q 2 12
;
proc catmod data=d1; direct a; weight w; model y = a; run; quit;
proc catmod data=d1; weight w; model y = x; direct x; run; quit;
proc catmod data=d1; direct nosuch; weight w; model y = x; run; quit;
