data vs;
  length trt $1;
  input trt $ sbp;
  datalines;
A 120
A 130
B 140
B 150
;
run;
proc means data=vs noprint;
  class trt;
  var sbp;
  output out=mo(keep=trt _freq_ mean) mean=mean;
run;
proc print data=mo noobs; run;
