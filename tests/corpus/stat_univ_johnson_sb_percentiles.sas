/* Fit bounded Johnson SB data by matching percentiles. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  do i=1 to 31;
    z=probit((i-.5)/31);
    x=1/(1+exp(-z));
    output;
  end;
run;

proc univariate data=sample;
  var x;
  histogram x / sb(fitmethod=percentile) noplot;
run;
