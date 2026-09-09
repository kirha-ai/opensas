data d;
  input x y z;
  datalines;
1 2 3
4 5 6
;
run;
proc transpose data=d out=t;
run;
proc print data=t noobs; run;
