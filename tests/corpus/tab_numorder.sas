data d; input g c v; datalines;
1 5 100
2 5 200
10 5 300
;
run;
proc tabulate data=d; class g; var v; table g, v*sum; run;
proc tabulate data=d; class g c; var v; table g, c*v*sum; run;
