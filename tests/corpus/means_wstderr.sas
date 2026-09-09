/* BUG-meanswstderr: weighted STDERR/T/PROBT/LCLM/UCLM divide by Σw (sum of
   weights), not n. x={1,2,3} w={2,2,2}: Σw=6, VAR=2, MEAN=2, so
   se=sqrt(2/6)=0.5773502692, t=2/se=3.4641016151, 95% CL = 2 ± t(.975,2)·se
   = -0.4841266527 .. 4.4841266527. n-based (wrong) would give se=0.8164965809. */
data d; input x w; datalines;
1 2
2 2
3 2
;
run;
proc means data=d mean var stderr t lclm uclm; var x; weight w; run;
proc means data=d noprint; var x; weight w;
  output out=o mean=mn var=vr stderr=se t=tv lclm=lo uclm=hi; run;
proc print data=o noobs; run;
