data d;
  input x;
  datalines;
1
2
3
4
5
6
7
8
;
run;

proc means data=d q1 median q3;
  var x;
run;
