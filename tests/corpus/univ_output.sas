data d;
  input v;
  datalines;
10
20
30
40
;
run;
proc univariate data=d noprint;
  var v;
  output out=ustats n=cnt mean=m std=s min=lo max=hi median=med;
run;
proc print data=ustats noobs; run;
