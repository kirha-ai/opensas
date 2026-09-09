/* QA regression: DEPSL / DEPSYD / DEPDB pinned against the values printed in
   SAS 9.4 Functions and CALL Routines: Reference (p.977 DEPDB, p.1006 DEPSL).
   The arguments are the manual's because its printed results are the oracle.
   DEPSL(period,value,life); DEPSYD(...); DEPDB(period,value,life,rate-factor). */
data _null_;
  straight   = depsl(1, 10000, 5);
  straightfr = depsl(9/12, 1000, 10);
  sumyears   = depsyd(1, 10000, 5);
  declining  = depdb(1, 10000, 5, 2);
  declining2 = depdb(10, 1000, 15, 2);
  put "straight-line=" straight;
  put "straight-line frac period=" straightfr;
  put "sum-of-years=" sumyears;
  put "double-declining yr1=" declining;
  put "double-declining yr10=" declining2;
run;
