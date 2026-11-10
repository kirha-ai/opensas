options nodate nonumber;
data d; input x y; datalines;
1 .
. 3
;
proc corr nomiss; var x y; run;
