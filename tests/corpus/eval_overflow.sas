%let a = %eval(9999999999 * 9999999999);
%let b = %eval(9223372036854775807 + 1);
%let c = %eval(-(-9223372036854775807 - 1));
data _null_;
  put "a=&a";
  put "b=&b";
  put "c=&c";
run;
%if %eval(9999999999 * 9999999999) > 0 %then %put NOTE_BIG;
