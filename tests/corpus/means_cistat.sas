data d; input x; datalines;
2
3
4
5
6
7
8
9
10
;
run;
proc means data=d n mean stderr clm t probt; var x; run;
