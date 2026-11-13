ods graphics off;
data d; input x @@; datalines;
1 2 3 4 6 8 10 15
;
proc univariate data=d noprint;
histogram x / noplot normal(mu=5 est sigma=est 2) lognormal(zeta=1 est sigma=est 1) exponential(theta=est 0 sigma=2 est) weibull(c=2) gamma(alpha=2) gumbel(mu=5) igauss(mu=5) rayleigh;
run;
