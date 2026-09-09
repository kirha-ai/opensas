/* Extended descriptive stats incl. quartiles, CV, std error (PROC MEANS) */
data lb; input AVAL; datalines;
10
20
30
40
.
;
run;
proc means data=lb n nmiss mean median q1 q3 std stderr cv range var sum min max;
  var AVAL;
run;
