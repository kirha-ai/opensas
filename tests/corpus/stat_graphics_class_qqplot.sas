/* Render a comparative Q-Q plot with different location and dispersion by class. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  length site $8; label site="Study site" x="Baseline" y="Follow-up";
  input site $ x y;
  datalines;
A 1 3
A 2 1
A 5 4
B 3 2
B 4 6
B 7 5
;
run;

ods listing gpath="%sysfunc(pathname(work))";
ods graphics on;
proc univariate data=sample;
  class site;
  var x;
  qqplot x / normal(mu=est sigma=est);
run;
ods graphics off;
