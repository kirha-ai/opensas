data sample;do i=1 to 101;z=probit((i-.375)/101.25);
b=1/(1+exp((.4-z)/1.2));output;end;run;
ods select ParameterEstimates;proc univariate data=sample;var b;histogram b / sb(fitmethod=mle gamma=.8) noplot;run;
