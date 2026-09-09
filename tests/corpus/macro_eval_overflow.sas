%let big = %eval(9999999999 * 9999999999);
data _null_;
  put "big=&big";
run;
