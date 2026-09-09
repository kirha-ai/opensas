data d;
  input g $ x;
  datalines;
b 1
a 2
b 3
a 4
c 5
b 9
;
run;
/* BUG-meansoptnoop: DESCENDING reverses the CLASS level order (c b a). */
proc means data=d descending n mean;
  class g;
  var x;
run;
/* ORDER=FREQ: descending group size (b=3 a=2 c=1); ORDER=DATA: first
   appearance (b a c). Neither warns "freq/data is not recognized". */
proc means data=d order=freq n mean;
  class g;
  var x;
run;
proc means data=d order=data n mean;
  class g;
  var x;
run;
