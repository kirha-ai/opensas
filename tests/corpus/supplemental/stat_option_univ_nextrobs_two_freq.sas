data sample;input g x y f;datalines;
. -2.5 -1.25 2
1 -1.5 -.75 1
1 -.5 -.25 3
1 .5 .25 1
2 1.5 .75 1
2 2.5 1.25 1
2 3.5 1.75 2
;
run;
ods select ExtremeObs;proc univariate data=sample nextrobs=2;var x;freq f;run;
