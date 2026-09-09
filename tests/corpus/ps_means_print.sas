data lb;
  length trt $1;
  input trt $ aval;
  datalines;
A 10
A 30
B 20
B 60
;
run;
proc means data=lb n mean std min max;
  class trt;
  var aval;
run;
