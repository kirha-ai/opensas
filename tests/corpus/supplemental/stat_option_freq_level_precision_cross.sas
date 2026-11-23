data d;input x y;datalines;
.123456789012355 1
.123456789045678 2
.123456789144444 2
.123456789944444 2
.123456789012345 2
-10 1
2 2
12 1
-2 2
;
run;
proc freq data=d nlevels order=formatted;tables y*x / out=o;run;data _null_;set o;file print;put 'CELL ' count 3.;run;
