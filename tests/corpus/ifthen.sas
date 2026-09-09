data _null_;
  x = 75;
  if x >= 90 then grade = "A";
  else if x >= 80 then grade = "B";
  else if x >= 70 then grade = "C";
  else grade = "F";
  put "grade=" grade;
run;
