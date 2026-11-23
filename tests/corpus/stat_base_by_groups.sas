options nodate nonumber;
data d; input x y z g h w f; datalines;
1 2 4 0 0 1 1
2 5 3 0 1 2 1
3 5 6 0 0 1 2
4 9 5 0 1 1 1
5 8 7 1 0 3 1
6 13 9 1 1 1 2
7 12 8 1 0 1 1
8 17 10 1 1 2 1
;

proc sort data=d; by g; run; proc corr data=d; by g; var x y; run; proc freq data=d; by g; tables h; run; proc univariate data=d; by g; var x; run;
