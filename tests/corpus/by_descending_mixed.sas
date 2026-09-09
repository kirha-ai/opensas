data have;
  input a b;
  datalines;
1 5
1 3
2 9
2 1
;
run;

data _null_;
  set have;
  by a descending b;
  if first.b then put "FB a=" a " b=" b;
  if last.a  then put "LA a=" a;
run;
