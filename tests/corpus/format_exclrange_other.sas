proc format;
  value grade 0-<10="LOW" 10-<20="MID";
run;
data _null_;
  do x = 0, 5, 9, 10, 15, 20, 99;
    g = put(x, grade.);
    put x= g=;
  end;
run;
