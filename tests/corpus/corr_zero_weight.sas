/* FEAT-corr-core: expect-rc: 1. SAS ERROR: Total weight is 0. */
data d; input x y w; datalines;
1 2 0
2 3 -1
;
proc corr; var x y; weight w; run;
