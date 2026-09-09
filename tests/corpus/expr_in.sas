data _null_;
  x = 2;
  if x in (1, 2, 3) then put "in yes";
  else put "in no";
  if x in (4, 5) then put "bad";
run;
