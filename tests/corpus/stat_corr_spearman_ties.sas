options nodate nonumber;
data d;
 input x y z g h w f;
 datalines;
1 2 4 0 0 1 1
2 5 3 0 1 2 1
3 5 6 0 0 1 2
4 9 5 0 1 1 1
5 8 7 1 0 3 1
6 13 9 1 1 1 2
7 12 8 1 0 1 1
8 17 10 1 1 2 1
;

proc corr data=d spearman; var x y; run;
