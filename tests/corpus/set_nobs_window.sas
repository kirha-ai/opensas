/* BUG-pointnobs (F2): NOBS= is the PHYSICAL observation count of the input
   dataset — a descriptor-level number. FIRSTOBS=/OBS= only window which
   observations are READ (1 row here); they do not shrink NOBS= (stays 3).
   Both producers (pre-loop init, per-read _setobs_ stamp) must agree. */
data d; input x; datalines;
10
20
30
;
run;
data _null_;
  set d(firstobs=2 obs=2) nobs=n;
  put 'WINDOW NOBS=' n;
run;
