data d;
  input g $ s $ r @@;
  datalines;
Z X 1  Z X 1  Z Y 0  A Y 1  A Y 1
;
run;

/* Z has 3 obs, A has 2 → ORDER=FREQ lists Z's stratum first */
proc freq data=d order=freq;
  tables g*s*r;
run;

/* Z appears first in the data → ORDER=DATA lists Z's stratum first */
proc freq data=d order=data;
  tables g*s*r;
run;

/* default ORDER=INTERNAL: strata ascending (A then Z) */
proc freq data=d;
  tables g*s*r;
run;
