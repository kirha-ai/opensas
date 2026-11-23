/* Fit unbounded Johnson SU data by matching percentiles. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  do i=1 to 31;
    z=probit((i-.5)/31);
    x=sinh(z);
    output;
  end;
run;

proc univariate data=sample;
  var x;
  histogram x / su(fitmethod=percentile) noplot;
run;
