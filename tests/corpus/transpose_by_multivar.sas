data d;
  length grp $1;
  input grp $ m1 m2;
  datalines;
A 10 20
B 30 40
;
run;
proc transpose data=d out=t;
  by grp;
  var m1 m2;
run;
proc print data=t noobs; run;
