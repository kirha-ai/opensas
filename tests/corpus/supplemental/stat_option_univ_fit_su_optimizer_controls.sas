data sample;do i=1 to 51;z=probit((i-.375)/51.25);x=2*sinh(z/1.1);output;end;run;
ods select ParameterEstimates;proc univariate data=sample;var x;histogram x / su(fitmethod=mle optseed=42 optmaxstarts=1 optboundrange=2 opttolerance=1e-10) noplot;run;
