data sample;
do i=1 to 31;
  z=probit((i-.5)/31);b=1/(1+exp(-z));u=sinh(z);output;
end;
run;
ods select ParameterEstimates;proc univariate data=sample;var u;histogram u / su(fitinterval=.68 fittolerance=.95) noplot;run;
