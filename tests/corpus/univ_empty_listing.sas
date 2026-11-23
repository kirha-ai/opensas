/* M9 empty_three: an empty input produces no listing. A populated input
   with only missing analysis values still produces a missing-values table. */
data empty;
  length x 8;
  stop;
run;
proc univariate data=empty;
  var x;
run;
data compare;
  x=1; output;
run;
proc univariate data=compare(where=(x=2));
  var x;
run;
data _null_;
  put 'completed both empty analyses';
run;
