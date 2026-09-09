data lb;
  length trt $1 param $3;
  input trt $ param $ aval;
  datalines;
A ALT 10
A AST 20
B ALT 30
B AST 40
;
run;
proc means data=lb noprint;
  class trt param;
  var aval;
  output out=stats mean=mean n=n;
run;
proc print data=stats noobs; run;
