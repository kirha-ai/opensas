/* Invented near-zero crossing controls; SAS evidence in stopping-fix. */
data d1;input x y f;datalines;
0 -5 55
0 3 102
0 5 193
7 -5 41
7 3 61
7 5 8
9 -5 71
9 3 97
9 5 67
;
proc corr data=d1 polychoric(converge=0.47484040973904063 maxiter=200) nosimple noprob;var x;with y;freq f;run;
data d2;input x y f;datalines;
-3 -6 218
-3 2 55
-3 9 310
3 -6 136
3 2 222
3 9 214
;
proc corr data=d2 polychoric(converge=0.49718716894559606 maxiter=200) nosimple noprob;var x;with y;freq f;run;
data d3;input x y f;datalines;
-6 -7 88
-6 0 190
-6 5 282
-5 -7 214
-5 0 329
-5 5 30
;
proc corr data=d3 polychoric(converge=0.37455900953057319 maxiter=200) nosimple noprob;var x;with y;freq f;run;
data d4;input x y f;datalines;
-4 -5 79
-4 3 214
-4 11 218
4 -5 292
4 3 134
4 11 75
;
proc corr data=d4 polychoric(converge=0.30662452789839933 maxiter=200) nosimple noprob;var x;with y;freq f;run;
