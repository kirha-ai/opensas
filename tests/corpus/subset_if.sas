data _null_;
  input n;
  if mod(n, 2) = 0;
  put "even=" n;
  datalines;
1
2
3
4
5
6
;
run;
