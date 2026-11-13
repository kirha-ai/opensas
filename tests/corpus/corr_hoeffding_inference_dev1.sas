data d;
input g x y f;
datalines;
1 1 3 1
1 2 7 1
1 3 1 1
1 4 8 1
1 5 2 1
1 6 6 1
1 7 4 1
1 8 5 1
2 1 1 1
2 2 2 1
2 3 3 1
2 4 4 1
2 5 5 1
3 1 1 1
3 2 2 1
3 3 3 1
3 4 4 1
3 5 5 1
3 6 6 1
4 1 3 2.9
4 1 1 1
4 2 2 3
4 3 3 1
4 4 1 2
4 100 -100 0
4 200 -200 .
5 1 1 1
5 2 4 1
5 3 2 1
5 4 6 1
5 5 3 1
5 6 5 1
5 7 . 1
5 . 7 1
6 1 1 1
6 2 1 1
6 3 1 1
6 4 1 1
6 5 1 1
6 6 1 1
7 1 1 1
7 2 2 1
7 3 3 1
7 4 4 1
;
proc corr data=d hoeffding nosimple; by g; var x; with y; freq f; run;
proc corr data=d hoeffding nosimple noprob; by g; var x; with y; freq f; run;
data expanded;set d;if f>=1 then do rep=1 to floor(f);output;end;run;
proc corr data=expanded hoeffding nosimple;by g;var x;with y;run;
