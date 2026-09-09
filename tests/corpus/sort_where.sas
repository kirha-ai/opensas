data d; input g $ v; datalines;
a 2
b 1
a 1
c 3
b 3
;
run;
proc sort data=d; where g in ("a" "b"); by v g; run;
proc print data=d noobs; run;
