options nodate nonumber;
data d; input x y w; datalines;
1 2 1
3 4 2
5 8 3
;
proc corr data=d cov csscp sscp; var x y; weight w; run;
proc corr data=d cov vardef=wdf; var x; with y; weight w; run;
data m; input x y w; datalines;
1 2 1
2 . 2
. 5 1
4 8 0
5 3 -2
7 4 3
;
proc corr data=m cov csscp sscp; var x; with y; weight w; run;
