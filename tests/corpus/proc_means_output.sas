data d;
  input g $ x;
  datalines;
A 10
B 100
A 20
B 200
;
run;
proc means data=d noprint; class g; var x; output out=o mean=avg sum=tot n=cnt; run;
proc print data=o noobs; run;
