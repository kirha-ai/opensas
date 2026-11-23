options nodate nonumber;
data d; input x y g h w f; datalines;
1 2 0 0 1 1
2 . 0 1 2 1
. 4 0 0 1 1
4 8 1 1 1 1
5 10 1 0 0 2
6 12 1 1 3 0
;

proc corr data=d; var x y; run;
