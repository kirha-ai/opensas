data d;
  input g $ x;
  datalines;
a 10
a 20
b 30
;
run;
proc means data=d nway noprint; class g; var x; output out=s mean=m; run;
proc print data=s noobs; run;
