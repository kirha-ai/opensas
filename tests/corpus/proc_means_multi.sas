data d;
  input x y;
  datalines;
1 10
2 20
3 30
;
run;

proc means data=d n mean sum;
  var x y;
run;
