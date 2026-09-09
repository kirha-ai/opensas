data _null_;
  input a b / c;
  put "a=" a " b=" b " c=" c;
  datalines;
1 2
3
4 5
6
;
run;
