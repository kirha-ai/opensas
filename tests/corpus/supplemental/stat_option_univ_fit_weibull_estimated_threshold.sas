data sample;do i=1 to 51;p=(i-.375)/51.25;x=2+quantile('gamma',p,3,2);output;end;run;
ods select ParameterEstimates;proc univariate data=sample;var x;histogram x / weibull(theta=est) noplot;run;
