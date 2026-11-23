/* Count standard and special missing values alongside a nonempty variable. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input x y;
  datalines;
. 1
.A 2
.Z .
._ 4
;
run;

proc univariate data=sample noprint;
  var x y;
  output out=counts n=nx ny nmiss=mx my mean=ax ay;
run;
proc print data=counts noobs;
run;
