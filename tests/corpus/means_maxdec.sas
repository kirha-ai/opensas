data d;
  input x;
  datalines;
1.23456
2.34567
3.45678
;
run;

proc means data=d maxdec=2;
  var x;
run;

proc means data=d maxdec=0;
  var x;
run;

proc means data=d;
  var x;
run;
