data have;
  input x y;
  datalines;
1 100
2 200
3 300
;
run;

proc means data=have n mean sum;
  var x y;
run;
