proc format;
  value agecat
    low - <18 = "Child"
    18 - <40 = "Young Adult"
    40 - <65 = "Middle Age"
    65 - high = "Senior";
run;
data _null_;
  length s $12;
  do a = 10, 18, 39, 40, 64, 65, 90;
    s = put(a, agecat.);
    put "age" a "=" s;
  end;
run;
