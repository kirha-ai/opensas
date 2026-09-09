data d;
  input g $ v;
  datalines;
a 10
a 20
b 30
b 50
;
run;
proc means data=d noprint; by g; var v; output out=ms mean=m n=cnt; run;
proc print data=ms noobs; run;
proc univariate data=d noprint; by g; var v; output out=us mean=um n=un; run;
proc print data=us noobs; run;
