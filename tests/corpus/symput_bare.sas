data _null_;
  call symput("cnt", "7");
run;
data _null_;
  n = &cnt + 1;
  put n=;
run;
