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
2 2 3 1
2 3 2 1
2 4 5 1
2 5 4 1
2 6 7 1
2 7 6 1
2 8 8 1
3 1 1 1
3 2 2 1
3 3 3 1
3 4 4 1
3 5 5 1
3 6 6 1
3 7 7 1
3 8 8 1
3 9 9 1
3 10 10 1
3 11 11 1
3 12 12 1
3 13 13 1
3 14 14 1
3 15 15 1
3 16 16 1
3 17 17 1
3 18 18 1
3 19 19 1
3 20 20 1
4 1 3 2
4 1 1 1
4 2 2 3
4 3 3 1
4 4 1 2
5 1 1 1
5 2 1 1
5 3 1 1
5 4 1 1
5 5 1 1
5 6 1 1
6 1 1 1
6 1 1 1
6 1 1 1
6 1 1 1
6 1 1 1
6 1 1 1
7 1 2 1
7 2 9 1
7 3 1 1
7 4 8 1
7 5 4 1
7 6 11 1
7 7 3 1
7 8 12 1
7 9 5 1
7 10 10 1
7 11 6 1
7 12 7 1
8 1 1 1
8 2 2 1
8 3 3 1
8 4 4 1
8 5 5 1
8 6 6 1
8 7 7 1
8 8 8 1
8 9 9 1
8 10 10 1
8 11 12 1
8 12 11 1
;
ods output HoeffdingCorr=h;
proc corr data=d hoeffding; by g; var x; with y; freq f; run;
proc print data=h; format _numeric_ best32.; run;
data expanded; set d; do rep=1 to f; output; end; run;
ods output HoeffdingCorr=he;
proc corr data=expanded hoeffding; by g; var x; with y; run;
proc print data=he; format _numeric_ best32.; run;
