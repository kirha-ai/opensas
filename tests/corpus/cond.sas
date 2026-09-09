data _null_;
  score = 72;
  if score >= 60 then grade = "PASS";
  else grade = "FAIL";
  put "grade=" grade;
run;
