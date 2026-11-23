data sample;input g x;datalines;
.A 8
._ 2
.Z 12
. 5
.A 10
1 26
;
run;
proc sort data=sample out=sorted;by g;run;proc corr data=sorted;by g;var x;run;
