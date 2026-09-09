data d;
  input g $ x;
  datalines;
A 10
A 20
B 5
B 15
;
run;
proc sort data=d; by g; run;
proc print data=d; by g; sum x; run;
