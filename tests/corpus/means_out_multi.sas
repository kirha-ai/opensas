data d; input g $ x y; datalines;
A 1 100
A 3 300
B 2 200
B 4 400
;
run;
proc means data=d noprint; var x y; output out=o mean=mx my n=nx ny; run;
proc print data=o noobs; run;
proc means data=d noprint; class g; var x y; output out=o2 mean(x y)=ax ay; run;
proc print data=o2 noobs; run;
