/* expect-rc: 1 */
data sample;input g1 g3 g2 x;datalines;
1 1 1 2
1 1 1 4
1 1 2 10
1 1 2 14
;
run;
proc sort data=sample out=down;by descending g2;run;proc corr data=down;by descending g1-g3;var x;run;
