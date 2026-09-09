data lb;
  length usubjid $4 trt $1;
  input usubjid $ trt $ aval;
  datalines;
S01 A 5.1
S02 A 6.3
S03 B 7.2
S04 B 8.8
;
run;
proc sql;
  create table stats as
    select trt, count(*) as n, mean(aval) as mean, max(aval) as max
    from lb group by trt;
quit;
proc print data=stats noobs; run;
