data d; input x y; datalines;
2 20
4 40
6 60
8 80
10 100
;
run;
proc means data=d noprint; var x y; output out=o; run;
proc print data=o noobs; run;
