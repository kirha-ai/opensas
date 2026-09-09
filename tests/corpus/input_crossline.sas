data d;
  input a b;
  datalines;
1
2
3
4
;
run;
data _null_;
  set d;
  put "obs " a= b=;
run;
