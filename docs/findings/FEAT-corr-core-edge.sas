options nodate nonumber;
data zero; input x y w; datalines;
1 2 0
2 3 -1
;
proc corr data=zero; var x y; weight w; run;
proc corr data=zero; var x y; where x>99; run;
data missing; input x y w; datalines;
. 1 1
. 2 1
. 3 1
;
proc corr data=missing; var x y; run;
data v; input x1 x2 w; datalines;
1 2 1
3 4 2
5 8 3
;
proc corr data=v vardef=n; var x1 x2; weight w; run;
proc corr data=v vardef=wdf; var x1 x2; weight w; run;
proc corr data=v; var x1; with x1 x2; run;
proc corr data=v; var x1; with x1; run;
data neg; input x y; datalines;
1 6
2 4
3 2
;
proc corr data=neg; var x y; run;
