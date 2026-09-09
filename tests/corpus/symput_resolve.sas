data _null_;
  call symput("a", "hello");
run;
data _null_;
  x = "&a";
  put x=;
run;
