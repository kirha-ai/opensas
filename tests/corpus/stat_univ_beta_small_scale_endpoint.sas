/* Estimate the upper endpoint with fixed lower threshold and one fixed shape, on a narrow support. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  do i=1 to 31;
    x=.01*quantile("beta",(i-.375)/31.25,2,3);
    output;
  end;
run;

proc univariate data=sample;
  var x;
  histogram x / beta(theta=0 sigma=est beta=1.5) noplot;
run;
