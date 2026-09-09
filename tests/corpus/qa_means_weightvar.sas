data d;
  input x w;
  datalines;
10 1
20 2
30 3
40 4
;
run;
proc means data=d n mean std var stderr cv;
  weight w;
  var x;
run;
