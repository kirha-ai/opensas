/* expect-rc: 1 */
data sample;input x @@;datalines;
1 2 3 4 6 8 10 15
;
run;
ods select ParameterEstimates;proc univariate data=sample;var x;histogram x / weibull(maxiter=1) noplot;run;
