/* FEAT-corr-core: SAS oracle one/two/three observations. */
data tiny; input g x y; datalines;
1 1 2
2 1 2
2 2 4
3 1 2
3 2 4
3 3 6
;
proc corr data=tiny; by g; var x y; run;
