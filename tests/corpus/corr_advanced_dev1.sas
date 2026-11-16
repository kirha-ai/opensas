data d;
input x y z f;
datalines;
1 2 1 2
2 5 3 1
3 5 2 1
4 9 4 1
5 8 3 2
6 13 5 1
7 12 4 1
8 17 6 1
;
proc corr data=d pearson spearman kendall fisher alpha; var x y z; run;
proc corr data=d pearson spearman kendall fisher; var x y; partial z; run;
proc corr data=d pearson spearman fisher(type=lower rho0=.5 alpha=.1 biasadj=no); var x; with y; freq f; run;

proc corr data=d hoeffding noprob; var x y z; run;

data poly;
input x y f;
datalines;
1 1 12
1 2 5
1 3 3
2 1 4
2 2 17
2 3 6
3 1 2
3 2 8
3 3 13
;
proc corr data=poly polychoric; var x y; freq f; run;
proc corr data=poly polyserial; var x; with y; freq f; run;
