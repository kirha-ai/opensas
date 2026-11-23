data sample;input x @@;datalines;
1 2 3 4 6 8 10 15
;
run;
ods select ParameterEstimates;proc univariate data=sample;var x;histogram x / gamma(alphainitial=.65 alphadelta=1 maxiter=5) noplot;run;
