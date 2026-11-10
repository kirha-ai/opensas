/* FEAT-corr-core: SAS reference r=.96204126289224, p=.0001. */
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
