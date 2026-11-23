data sample;input g x;datalines;
.A 1
._ 2
.Z 1
. 2
.A 2
2 1
1 1
;
run;
proc freq data=sample;tables g*x / list missing;run;
