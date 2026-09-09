data ae; input id $ @@; datalines;
s1 s1 s2 s3 s3
;
run;
proc sql;
  create table c as select count(distinct id) as n from ae;
quit;
data _null_; set c; put "distinct " n=; run;
