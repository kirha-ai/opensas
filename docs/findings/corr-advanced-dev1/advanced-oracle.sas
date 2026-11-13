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
proc corr data=d pearson spearman kendall hoeffding fisher alpha; var x y z; run;
proc corr data=d pearson spearman kendall fisher; var x y; partial z; run;
proc corr data=d pearson spearman fisher(type=lower rho0=.5 alpha=.1 biasadj=no); var x; with y; freq f; run;
