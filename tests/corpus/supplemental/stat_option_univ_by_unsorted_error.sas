/* expect-rc: 1 */
data sample; input g x y; datalines;
2 2 2
1 1 1
;
run;
proc univariate data=sample; by g; var x; run;
