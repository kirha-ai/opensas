/* Fit an asymmetric Johnson SU sample with seeded optimizer starting values. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  do i=1 to 31;
    z=probit((i-.5)/31);
    x=4+1.5*sinh((z-.7)/1.4);
    output;
  end;
run;

proc univariate data=sample;
  var x;
  histogram x / su(fitmethod=mle optseed=701) noplot;
run;
