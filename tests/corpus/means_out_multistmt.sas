/* BUG-meansoutmultistmt: EACH OUTPUT statement in PROC MEANS builds its OWN
   output dataset with its OWN stat list — SAS never merges two OUTPUT
   statements into one. opensas used a single out_name slot + one shared spec
   list: the 2nd statement overwrote the name and appended its specs, so `a`
   was never created and `b` got ALL columns concatenated.
   SAS-expected: a=(_TYPE_=0,_FREQ_=3,m=20); b=(_TYPE_=0,_FREQ_=3,s=10). */
data d;
  input x;
  datalines;
10
20
30
;
run;
proc means data=d noprint;
  var x;
  output out=a mean=m;
  output out=b std=s;
run;
proc print data=a noobs; run;
proc print data=b noobs; run;
