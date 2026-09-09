data ex;
  length trt $1;
  input trt $ dose;
  datalines;
A 5
A 10
A 15
B 20
B 40
;
run;
proc summary data=ex noprint nway;
  class trt;
  var dose;
  output out=so mean=mean sum=sum n=n;
run;
proc print data=so noobs; run;
