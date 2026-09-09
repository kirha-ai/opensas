data lb;
  length trt $1;
  input trt $ aval;
  datalines;
A 10
A 20
B 40
B 50
C 5
C 7
;
run;
proc sql;
  create table hi_arms as select trt, avg(aval) as mean_aval
    from lb group by trt having avg(aval) > 15;
quit;
proc print data=hi_arms noobs; run;
