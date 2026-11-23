/* expect-rc: 1 */
data sample; input g x y; datalines;
2 2 2
1 1 1
;
run;
proc corr data=sample; by g; var x y; run;
