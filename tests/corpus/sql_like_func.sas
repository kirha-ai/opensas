/* GH#28: LIKE/BETWEEN/CONTAINS accept a function-call left operand */
data a;
  length c $200;
  input c $30.;
  datalines;
vitamin d3
VITAMIN B12
placebo
;
run;
proc sql;
  create table lo as select c from a where lowcase(c) like 'vitamin d%';
  create table su as select c from a where substr(c,1,7) like 'vitamin%';
quit;
data _null_; set lo; put "lo=" c; run;
data _null_; set su; put "su=" c; run;
