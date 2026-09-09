data d;
  input v @@;
  datalines;
2 4 4 4 5 5 7 9
;
run;
proc means data=d n mean std var cv stderr range;
  var v;
run;
