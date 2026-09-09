data _null_;
  input v;
  n + 1;
  if n > 3 then stop;
  put "obs" n "v=" v;
  datalines;
10
20
30
40
50
;
run;
