ods graphics off;
data d; input x @@; datalines;
0.02 0.05 0.1 0.15 0.2 0.3 0.45 0.6 0.75 0.9 0.95 0.99
;
proc univariate data=d noprint; histogram x / noplot beta(alpha=est 2 beta=est 3) power;run;
data d; input x @@; datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint; histogram x / noplot gumbel(mu=est 5 sigma=est est);run;
