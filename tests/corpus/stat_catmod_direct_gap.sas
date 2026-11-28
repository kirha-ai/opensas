/* expect-rc: 2
   STAT-CATMOD-003 boundary (D-009 gaps, no table): DIRECT with a
   POPULATION statement (population order unverified), a DIRECT variable
   in a nested effect, a format grouping several DIRECT values (SAS uses
   the FIRST internal value, p. 2196), FACTORS (needs the TYPE=EST
   RESPONSE READ input and _RESPONSE_ of STAT-CATMOD-004) and LOGLIN (needs
   multiple response variables and _RESPONSE_ of STAT-CATMOD-004).
   Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data d1; input x b y w @@; datalines;
1 1 1 10 1 2 2 5 2 1 1 8 2 2 2 7 3 1 1 4 3 2 2 11 4 1 1 3 4 2 2 12
1 1 2 2 1 2 1 3 2 1 2 4 2 2 1 2 3 1 2 5 3 2 1 3 4 1 2 6 4 2 1 1
;
proc format; value grp 1,2='low' 3,4='high'; run;
data d1g; set d1; format x grp.; run;
proc catmod data=d1; direct x; weight w; population x b; model y = x; run; quit;
proc catmod data=d1; direct x; weight w; model y = x(b); run; quit;
proc catmod data=d1; direct x; weight w; model y = b(x); run; quit;
proc catmod data=d1g; direct x; weight w; model y = x; run; quit;
proc catmod data=d1; weight w; model y = x; factors f 2; run; quit;
proc catmod data=d1; weight w; model b*y = _response_; loglin b y; run; quit;
