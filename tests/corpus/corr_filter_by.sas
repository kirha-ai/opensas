/* FEAT-corr-core: filters, WITH order, default VAR exclusions, descending BY. */
data d;
input g x y z w f;
datalines;
2 1 2 7 1 1
2 2 4 7 2 2.9
2 3 3 7 1 1
1 4 8 7 1 1
1 5 7 7 2 1
1 6 9 7 1 1
;
proc corr data=d(where=(x>1)); by descending g; with y; weight w; freq f; where x<6; run;
proc corr data=d nomiss nosimple noprob; var z x; with y; run;
proc corr data=d noprint; var x y; run;
proc print data=d noobs; var x; run;
