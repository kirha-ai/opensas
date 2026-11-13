ods graphics off;
data d;input x @@;datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint;histogram x / noplot weibull(itprint) endpoints=0 to 20 by 5;run;
proc univariate data=d noprint;histogram x / noplot weibull(itprint maxiter=5) endpoints=0 to 20 by 5 outhistogram=short;run;
proc univariate data=d noprint;histogram x / noplot weibull(itprint c=2 sigma=5 noprint) endpoints=0 to 20 by 5;run;
proc print data=short;run;
