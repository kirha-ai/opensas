data vs;
  length trt $1;
  input trt $ visit sbp;
  datalines;
A 1 120
A 2 118
B 1 130
B 2 128
;
run;
proc means data=vs nway noprint;
  class trt;
  var sbp;
  output out=nw mean=mean min=min max=max;
run;
proc print data=nw noobs; run;
