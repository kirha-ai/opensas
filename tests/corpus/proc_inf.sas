data d;
  x = 1e400;
  y = 5;
  output;
run;
proc print data=d; run;
proc means data=d sum mean max;
  var x y;
run;
