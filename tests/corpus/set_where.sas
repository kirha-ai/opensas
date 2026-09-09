data src;
  input v;
  datalines;
1
5
2
9
;
run;

data _null_;
  set src(where=(v > 3));
  put "v=" v;
run;
