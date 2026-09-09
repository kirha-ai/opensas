data _null_;
  x = .;
  y = x + 5;
  if x < 0 then flag = "yes";
  else flag = "no";
  put "y=" y;
  put "flag=" flag;
run;
