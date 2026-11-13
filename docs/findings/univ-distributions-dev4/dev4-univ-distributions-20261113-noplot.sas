ods graphics off;
data d; input x @@; datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint;
histogram x / noplot normal(mu=5) exponential(theta=est) gamma lognormal weibull rayleigh gumbel igauss pareto kernel(k=n q t c=0.5 lower=0) endpoints=0 to 20 by 5 outhistogram=oh outkernel=ok;
run;
proc print data=oh;run;
proc print data=ok(obs=5);run;
