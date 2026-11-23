data sample;do i=1 to 77;z=probit((i-.375)/77.25);
b=-2+5/(1+exp((-.7-z)/.8));u=-4+1.5*sinh((z+.65)/.9);output;end;run;
ods select ParameterEstimates;proc univariate data=sample;var b;histogram b / sb(fitmethod=mle theta=-2 sigma=5) noplot;run;
