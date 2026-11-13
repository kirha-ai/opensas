ods graphics off;
data d;do i=1 to 51;p=(i-.375)/(51+.25);x=2+quantile('gamma',p,3,2);output;end;run;
proc univariate data=d noprint;histogram x / noplot gamma(theta=est) lognormal(theta=est) weibull(theta=est) pareto;run;
