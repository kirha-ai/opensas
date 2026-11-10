options nodate nonumber;
data d;
input x y;
datalines;
1 2
2 5
3 5
4 9
5 8
6 13
7 12
8 17
;
proc corr data=d; var x y; run;
data m;
input x y z w f;
datalines;
1 2 7 1 1
2 . 7 2 2.9
. 5 7 1 1
4 8 7 0 3
5 3 7 -2 1
6 9 7 . 1
7 4 . 3 2
8 11 7 2 0
9 12 7 1 .
;
proc corr data=m; var y x z; weight w; freq f; run;
proc corr data=m nomiss; var y x z; weight w; freq f; run;
proc corr data=m exclnpwgt; var x; with y z; weight w; freq f; run;
data tiny; input g x y; datalines;
1 1 2
2 1 2
2 2 4
3 1 2
3 2 4
3 3 6
;
proc corr data=tiny; by g; var x y; run;
