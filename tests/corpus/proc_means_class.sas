data d;
  input g $ x;
  datalines;
A 10
B 100
A 20
B 200
A 30
;
run;
proc means data=d n mean; class g; var x; run;
