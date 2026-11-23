/* expect-rc: 1 */
data sample;input g h x;datalines;
2 2 1
1 2 3
2 1 4
1 1 8
;
run;
proc univariate data=sample;by g notsorted;by h;var x;run;
