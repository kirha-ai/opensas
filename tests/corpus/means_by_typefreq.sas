data d; input g $ x; datalines;
A 10
A 20
B 100
B 200
;
run;
proc means data=d noprint; by g; var x; output out=o mean=m; run;
proc print data=o noobs; run;
proc means data=d noprint; var x; output out=o2 mean=m; run;
proc print data=o2 noobs; run;
