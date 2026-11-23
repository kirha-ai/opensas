/* Use a nonuniform null in an exact multinomial goodness-of-fit test. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input level n;
  datalines;
1 1
2 3
3 2
;
run;

ods graphics off;
proc freq data=sample;
  weight n / zeros;
  tables level / chisq(testp=(.2 .3 .5));
  exact lrchi / point;
run;
